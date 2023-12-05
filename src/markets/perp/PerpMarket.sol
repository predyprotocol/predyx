// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {ReentrancyGuard} from "@solmate/src/utils/ReentrancyGuard.sol";
import "../../interfaces/IPredyPool.sol";
import "../../interfaces/ILendingPool.sol";
import "../../interfaces/IFillerMarket.sol";
import "../../interfaces/IOrderValidator.sol";
import "../../base/BaseMarket.sol";
import "../../libraries/orders/Permit2Lib.sol";
import "../../libraries/orders/ResolvedOrder.sol";
import {SlippageLib} from "../../libraries/SlippageLib.sol";
import {Bps} from "../../libraries/math/Bps.sol";
import "./PerpOrder.sol";
import {PredyPoolQuoter} from "../../lens/PredyPoolQuoter.sol";

/**
 * @notice Perp market contract
 */
contract PerpMarket is IFillerMarket, BaseMarket, ReentrancyGuard {
    using ResolvedOrderLib for ResolvedOrder;
    using PerpOrderLib for PerpOrder;
    using Permit2Lib for ResolvedOrder;
    using SafeTransferLib for ERC20;

    struct UserPosition {
        uint256 vaultId;
        uint256 takeProfitPrice;
        uint256 stopLossPrice;
        uint64 slippageTolerance;
    }

    enum CallbackSource {
        TRADE,
        CLOSE
    }

    struct CallbackData {
        CallbackSource callbackSource;
        address trader;
        int256 marginAmountUpdate;
    }

    IPermit2 private immutable _permit2;

    mapping(address owner => mapping(uint256 pairId => UserPosition)) public userPositions;

    event PerpTraded(
        address indexed trader,
        uint256 pairId,
        uint256 vaultId,
        int256 tradeAmount,
        IPredyPool.Payoff payoff,
        int256 fee,
        int256 marginAmount
    );
    event PerpClosedByTPSLOrder(
        address indexed trader,
        uint256 pairId,
        int256 tradeAmount,
        IPredyPool.Payoff payoff,
        int256 fee,
        uint256 closeValue
    );
    event PerpTPSLOrderUpdated(address indexed trader, uint256 pairId, uint256 takeProfitPrice, uint256 stopLossPrice);

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
        ERC20 quoteToken = ERC20(_getQuoteTokenAddress(tradeParams.pairId));

        if (tradeResult.minMargin == 0 || callbackData.callbackSource == CallbackSource.CLOSE) {
            DataType.Vault memory vault = _predyPool.getVault(tradeParams.vaultId);

            uint256 closeValue = uint256(vault.margin);

            ILendingPool(address(_predyPool)).take(true, address(this), closeValue);

            quoteToken.safeTransfer(callbackData.trader, closeValue);

            if (callbackData.callbackSource == CallbackSource.CLOSE) {
                emit PerpClosedByTPSLOrder(
                    owner, tradeParams.pairId, tradeParams.tradeAmount, tradeResult.payoff, tradeResult.fee, closeValue
                );
            }
        } else {
            int256 marginAmountUpdate = callbackData.marginAmountUpdate;

            if (marginAmountUpdate > 0) {
                quoteToken.safeTransfer(address(_predyPool), uint256(marginAmountUpdate));
            } else if (marginAmountUpdate < 0) {
                ILendingPool(address(_predyPool)).take(true, address(this), uint256(-marginAmountUpdate));

                quoteToken.safeTransfer(callbackData.trader, uint256(-marginAmountUpdate));
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
        nonReentrant
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        PerpOrder memory perpOrder = abi.decode(order.order, (PerpOrder));
        ResolvedOrder memory resolvedOrder = PerpOrderLib.resolve(perpOrder, order.sig);

        validateQuoteTokenAddress(perpOrder.pairId, perpOrder.entryTokenAddress);

        _verifyOrder(resolvedOrder);

        UserPosition storage userPosition = userPositions[perpOrder.info.trader][perpOrder.pairId];

        _saveUserPosition(
            userPosition,
            perpOrder.info.trader,
            perpOrder.pairId,
            perpOrder.takeProfitPrice,
            perpOrder.stopLossPrice,
            perpOrder.slippageTolerance
        );

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                perpOrder.pairId,
                userPosition.vaultId,
                perpOrder.tradeAmount,
                0,
                abi.encode(CallbackData(CallbackSource.TRADE, perpOrder.info.trader, perpOrder.marginAmount))
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

        IOrderValidator(perpOrder.validatorAddress).validate(
            perpOrder.tradeAmount, 0, perpOrder.validationData, tradeResult
        );

        emit PerpTraded(
            perpOrder.info.trader,
            perpOrder.pairId,
            tradeResult.vaultId,
            perpOrder.tradeAmount,
            tradeResult.payoff,
            tradeResult.fee,
            perpOrder.marginAmount
        );

        return tradeResult;
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
        nonReentrant
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
                abi.encode(CallbackData(CallbackSource.CLOSE, owner, 0))
            ),
            settlementData
        );

        SlippageLib.checkPrice(sqrtPrice, tradeResult, userPosition.slippageTolerance, 0);
    }

    function _saveUserPosition(
        UserPosition storage userPosition,
        address trader,
        uint256 pairId,
        uint256 takeProfitPrice,
        uint256 stopLossPrice,
        uint64 slippageTolerance
    ) internal {
        require(slippageTolerance <= Bps.ONE);

        userPosition.takeProfitPrice = takeProfitPrice;
        userPosition.stopLossPrice = stopLossPrice;
        userPosition.slippageTolerance = slippageTolerance + Bps.ONE;

        emit PerpTPSLOrderUpdated(trader, pairId, takeProfitPrice, stopLossPrice);
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
