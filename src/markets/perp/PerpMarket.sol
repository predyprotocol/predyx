// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IPredyPool.sol";
import "../../interfaces/ILendingPool.sol";
import "../../interfaces/IFillerMarket.sol";
import "../../interfaces/IOrderValidator.sol";
import "../../base/BaseMarket.sol";
import "../../libraries/orders/Permit2Lib.sol";
import "../../libraries/orders/ResolvedOrder.sol";
import "../../libraries/logic/LiquidationLogic.sol";
import "./PerpOrder.sol";
import "../../libraries/math/Math.sol";
import {PredyPoolQuoter} from "../../lens/PredyPoolQuoter.sol";

/**
 * @notice Perp market contract
 */
contract PerpMarket is IFillerMarket, BaseMarket {
    using ResolvedOrderLib for ResolvedOrder;
    using PerpOrderLib for PerpOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;

    struct UserPosition {
        uint256 vaultId;
        address canceler;
        uint256 takeProfitPrice;
        uint256 stopLossPrice;
        uint64 slippageTolerance;
    }

    struct CallbackData {
        address trader;
        int256 marginAmountUpdate;
    }

    IPermit2 private immutable _permit2;

    mapping(address owner => mapping(uint256 pairId => UserPosition)) public userPositions;

    event Traded(address trader, uint256 pairId, uint256 vaultId, uint256 takeProfitPrice, uint256 stopLossPrice);
    event ClosedByTPSLOrder(address trader, uint256 pairId, uint256 vaultId);
    event TPSLOrderCancelled(address trader, uint256 pairId, address canceler);

    constructor(IPredyPool predyPool, address permit2Address, address whitelistFiller)
        BaseMarket(predyPool, whitelistFiller)
    {
        _permit2 = IPermit2(permit2Address);
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallback) onlyPredyPool {
        CallbackData memory callbackData = abi.decode(tradeParams.extraData, (CallbackData));

        if (tradeResult.minMargin == 0) {
            DataType.Vault memory vault = _predyPool.getVault(tradeParams.vaultId);

            ILendingPool(address(_predyPool)).take(true, address(this), uint256(vault.margin));

            TransferHelper.safeTransfer(
                _getQuoteTokenAddress(tradeParams.pairId), callbackData.trader, uint256(vault.margin)
            );
        } else {
            int256 marginAmountUpdate = callbackData.marginAmountUpdate;

            if (marginAmountUpdate > 0) {
                TransferHelper.safeTransfer(
                    _getQuoteTokenAddress(tradeParams.pairId), address(_predyPool), uint256(marginAmountUpdate)
                );
            } else if (marginAmountUpdate < 0) {
                ILendingPool(address(_predyPool)).take(true, address(this), uint256(-marginAmountUpdate));

                TransferHelper.safeTransfer(
                    _getQuoteTokenAddress(tradeParams.pairId), callbackData.trader, uint256(-marginAmountUpdate)
                );
            }
        }
    }

    /**
     * @notice Verifies signature of the order and executes trade
     * @param order The order signed by trader
     * @param settlementData The route of settlement created by filler
     */
    function executeOrder(SignedOrder memory order, ISettlement.SettlementData memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        PerpOrder memory perpOrder = abi.decode(order.order, (PerpOrder));
        ResolvedOrder memory resolvedOrder = PerpOrderLib.resolve(perpOrder, order.sig);

        validateQuoteTokenAddress(perpOrder.pairId, perpOrder.entryTokenAddress);

        _verifyOrder(resolvedOrder);

        UserPosition storage userPosition = userPositions[perpOrder.info.trader][perpOrder.pairId];

        if (userPosition.vaultId == 0) {
            _saveUserPosition(
                userPosition,
                perpOrder.canceler,
                perpOrder.takeProfitPrice,
                perpOrder.stopLossPrice,
                perpOrder.slippageTolerance
            );
        }

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                perpOrder.pairId,
                userPosition.vaultId,
                perpOrder.tradeAmount,
                0,
                abi.encode(CallbackData(perpOrder.info.trader, perpOrder.marginAmount))
            ),
            settlementData
        );

        if (tradeResult.minMargin > 0) {
            // only whitelisted filler can open position
            if (msg.sender != _whitelistFiller) {
                revert CallerIsNotFiller();
            }
        }

        if (userPosition.vaultId == 0) {
            userPosition.vaultId = tradeResult.vaultId;

            _predyPool.updateRecepient(tradeResult.vaultId, perpOrder.info.trader);
        }

        if (perpOrder.validatorAddress != address(0)) {
            IOrderValidator(perpOrder.validatorAddress).validate(perpOrder, tradeResult);
        }

        emit Traded(
            perpOrder.info.trader,
            perpOrder.pairId,
            tradeResult.vaultId,
            perpOrder.takeProfitPrice,
            perpOrder.stopLossPrice
        );

        return tradeResult;
    }

    function cancelOrder(address owner, uint256 pairId) external {
        UserPosition storage userPosition = userPositions[owner][pairId];

        require(owner == msg.sender || userPosition.canceler == msg.sender);

        userPosition.takeProfitPrice = 0;
        userPosition.stopLossPrice = 0;

        emit TPSLOrderCancelled(owner, pairId, msg.sender);
    }

    /**
     * @notice Closes a position if TakeProfit/StopLoss condition is met.
     * @param owner owner address
     * @param pairId The id of pair
     * @param settlementData The route of settlement created by filler
     * @return tradeResult The result of trade
     * @dev Anyone can call this function
     */
    function close(address owner, uint256 pairId, ISettlement.SettlementData memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        UserPosition storage userPosition = userPositions[owner][pairId];

        require(userPosition.vaultId > 0);

        DataType.Vault memory vault = _predyPool.getVault(userPosition.vaultId);

        uint256 sqrtPrice = _predyPool.getSqrtIndexPrice(vault.openPosition.pairId);

        _validateTPSLCondition(vault.openPosition.perp.amount > 0, userPosition, sqrtPrice);

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                vault.openPosition.pairId,
                userPosition.vaultId,
                -vault.openPosition.perp.amount,
                -vault.openPosition.sqrtPerp.amount,
                abi.encode(CallbackData(owner, 0))
            ),
            settlementData
        );

        LiquidationLogic.checkPrice(
            sqrtPrice, tradeResult, userPosition.slippageTolerance, vault.openPosition.sqrtPerp.amount != 0
        );

        emit ClosedByTPSLOrder(owner, pairId, userPosition.vaultId);
    }

    function _saveUserPosition(
        UserPosition storage userPosition,
        address canceler,
        uint256 takeProfitPrice,
        uint256 stopLossPrice,
        uint64 slippageTolerance
    ) internal {
        require(slippageTolerance <= Bps.ONE);

        userPosition.canceler = canceler;
        userPosition.takeProfitPrice = takeProfitPrice;
        userPosition.stopLossPrice = stopLossPrice;
        userPosition.slippageTolerance = slippageTolerance + Bps.ONE;
    }

    function _validateTPSLCondition(bool isLong, UserPosition memory userPosition, uint256 sqrtIndexPrice)
        internal
        pure
    {
        if (isLong) {
            require(
                (0 < userPosition.stopLossPrice && sqrtIndexPrice <= userPosition.stopLossPrice)
                    || (0 < userPosition.takeProfitPrice && userPosition.takeProfitPrice <= sqrtIndexPrice)
            );
        } else {
            require(
                (0 < userPosition.takeProfitPrice && sqrtIndexPrice <= userPosition.takeProfitPrice)
                    || (0 < userPosition.stopLossPrice && userPosition.stopLossPrice <= sqrtIndexPrice)
            );
        }
    }

    function quoteExecuteOrder(
        PerpOrder memory perpOrder,
        ISettlement.SettlementData memory settlementData,
        PredyPoolQuoter quoter
    ) external {
        // Execute the trade for the user position in the filler pool
        IPredyPool.TradeResult memory tradeResult = quoter.quoteTrade(
            IPredyPool.TradeParams(
                perpOrder.pairId,
                userPositions[perpOrder.info.trader][perpOrder.pairId].vaultId,
                perpOrder.tradeAmount,
                0,
                bytes("")
            ),
            settlementData
        );

        revertTradeResult(tradeResult);
    }

    function revertTradeResult(IPredyPool.TradeResult memory tradeResult) internal pure {
        bytes memory data = abi.encode(tradeResult);

        assembly {
            revert(add(32, data), mload(data))
        }
    }

    function _verifyOrder(ResolvedOrder memory order) internal {
        order.validate();

        _permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(address(this)),
            order.info.trader,
            order.hash,
            PerpOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }
}
