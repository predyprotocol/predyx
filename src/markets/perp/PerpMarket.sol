// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../../interfaces/IPredyPool.sol";
import "../../interfaces/ILendingPool.sol";
import "../../interfaces/IOrderValidator.sol";
import {BaseMarketUpgradable} from "../../base/BaseMarketUpgradable.sol";
import {BaseHookCallbackUpgradable} from "../../base/BaseHookCallbackUpgradable.sol";
import "../../libraries/orders/Permit2Lib.sol";
import "../../libraries/orders/ResolvedOrder.sol";
import {SlippageLib} from "../../libraries/SlippageLib.sol";
import {Bps} from "../../libraries/math/Bps.sol";
import {Math} from "../../libraries/math/Math.sol";
import "./PerpOrder.sol";
import {PredyPoolQuoter} from "../../lens/PredyPoolQuoter.sol";

/**
 * @notice Perp market contract
 */
contract PerpMarket is Initializable, BaseMarketUpgradable, ReentrancyGuard {
    using ResolvedOrderLib for ResolvedOrder;
    using PerpOrderLib for PerpOrder;
    using Permit2Lib for ResolvedOrder;
    using SafeTransferLib for ERC20;

    error TPSLConditionDoesNotMatch();

    struct UserPosition {
        uint256 vaultId;
        uint256 takeProfitPrice;
        uint256 stopLossPrice;
        uint64 slippageTolerance;
        uint8 lastLeverage;
    }

    enum CallbackSource {
        TRADE,
        CLOSE,
        QUOTE
    }

    struct CallbackData {
        CallbackSource callbackSource;
        address trader;
        int256 marginAmountUpdate;
        address validatorAddress;
        bytes validationData;
    }

    IPermit2 private _permit2;

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

    constructor() {}

    function initialize(IPredyPool predyPool, address permit2Address, address whitelistFiller, address quoterAddress)
        public
        initializer
    {
        __BaseMarket_init(predyPool, whitelistFiller, quoterAddress);

        _permit2 = IPermit2(permit2Address);
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallbackUpgradable) onlyPredyPool {
        CallbackData memory callbackData = abi.decode(tradeParams.extraData, (CallbackData));
        ERC20 quoteToken = ERC20(_getQuoteTokenAddress(tradeParams.pairId));

        if (callbackData.callbackSource == CallbackSource.QUOTE) {
            IOrderValidator(callbackData.validatorAddress).validate(
                tradeParams.tradeAmount, 0, callbackData.validationData, tradeResult
            );

            _revertTradeResult(tradeResult);
        } else if (tradeResult.minMargin == 0 || callbackData.callbackSource == CallbackSource.CLOSE) {
            DataType.Vault memory vault = _predyPool.getVault(tradeParams.vaultId);

            uint256 closeValue = uint256(vault.margin);

            ILendingPool(address(_predyPool)).take(true, callbackData.trader, closeValue);

            if (callbackData.callbackSource == CallbackSource.CLOSE) {
                emit PerpClosedByTPSLOrder(
                    callbackData.trader,
                    tradeParams.pairId,
                    tradeParams.tradeAmount,
                    tradeResult.payoff,
                    tradeResult.fee,
                    closeValue
                );
            }
        } else if (callbackData.callbackSource == CallbackSource.TRADE) {
            int256 marginAmountUpdate = callbackData.marginAmountUpdate;

            if (marginAmountUpdate > 0) {
                quoteToken.safeTransfer(address(_predyPool), uint256(marginAmountUpdate));
            } else if (marginAmountUpdate < 0) {
                ILendingPool(address(_predyPool)).take(true, callbackData.trader, uint256(-marginAmountUpdate));
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

        _validateQuoteTokenAddress(perpOrder.pairId, perpOrder.entryTokenAddress);

        _verifyOrder(resolvedOrder);

        UserPosition storage userPosition = userPositions[perpOrder.info.trader][perpOrder.pairId];

        _saveUserPosition(userPosition, perpOrder);

        if (perpOrder.tradeAmount == 0 && perpOrder.marginAmount == 0) {
            return tradeResult;
        }

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                perpOrder.pairId,
                userPosition.vaultId,
                perpOrder.tradeAmount,
                0,
                abi.encode(
                    CallbackData(
                        CallbackSource.TRADE, perpOrder.info.trader, perpOrder.marginAmount, address(0), bytes("")
                    )
                )
            ),
            settlementData
        );

        if (tradeResult.minMargin > 0) {
            // only whitelisted filler can open position
            if (msg.sender != whitelistFiller) {
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

        bool slConditionMet = _getSLCondition(vault.openPosition.perp.amount > 0, userPosition, sqrtPrice);

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                vault.openPosition.pairId,
                userPosition.vaultId,
                -vault.openPosition.perp.amount,
                -vault.openPosition.sqrtPerp.amount,
                abi.encode(CallbackData(CallbackSource.CLOSE, owner, 0, address(0), bytes("")))
            ),
            settlementData
        );

        if (slConditionMet) {
            SlippageLib.checkPrice(sqrtPrice, tradeResult, userPosition.slippageTolerance, 0);
        } else {
            if (!_getTPCondition(vault.openPosition.perp.amount > 0, userPosition, Math.abs(tradeResult.averagePrice)))
            {
                revert TPSLConditionDoesNotMatch();
            }
        }
    }

    function getUserPosition(address owner, uint256 pairId)
        external
        returns (UserPosition memory userPosition, IPredyPool.VaultStatus memory, DataType.Vault memory)
    {
        userPosition = userPositions[owner][pairId];

        return (userPosition, _quoter.quoteVaultStatus(userPosition.vaultId), _predyPool.getVault(userPosition.vaultId));
    }

    function _saveUserPosition(UserPosition storage userPosition, PerpOrder memory perpOrder) internal {
        require(perpOrder.slippageTolerance <= Bps.ONE);

        userPosition.takeProfitPrice = perpOrder.takeProfitPrice;
        userPosition.stopLossPrice = perpOrder.stopLossPrice;
        userPosition.slippageTolerance = perpOrder.slippageTolerance + Bps.ONE;
        userPosition.lastLeverage = perpOrder.leverage;

        emit PerpTPSLOrderUpdated(
            perpOrder.info.trader, perpOrder.pairId, perpOrder.takeProfitPrice, perpOrder.stopLossPrice
        );
    }

    function _getSLCondition(bool isLong, UserPosition memory userPosition, uint256 sqrtIndexPrice)
        internal
        pure
        returns (bool)
    {
        uint256 priceX96 = Math.calSqrtPriceToPrice(sqrtIndexPrice);

        if (userPosition.stopLossPrice == 0) {
            return false;
        }

        if (isLong) {
            return priceX96 <= userPosition.stopLossPrice;
        } else {
            return userPosition.stopLossPrice <= priceX96;
        }
    }

    function _getTPCondition(bool isLong, UserPosition memory userPosition, uint256 averagePrice)
        internal
        pure
        returns (bool)
    {
        if (userPosition.takeProfitPrice == 0) {
            return false;
        }

        if (isLong) {
            return userPosition.takeProfitPrice <= averagePrice;
        } else {
            return averagePrice <= userPosition.takeProfitPrice;
        }
    }

    /// @notice Estimate transaction results and return with revert message
    function quoteExecuteOrder(PerpOrder memory perpOrder, ISettlement.SettlementData memory settlementData) external {
        _predyPool.trade(
            IPredyPool.TradeParams(
                perpOrder.pairId,
                userPositions[perpOrder.info.trader][perpOrder.pairId].vaultId,
                perpOrder.tradeAmount,
                0,
                abi.encode(
                    CallbackData(
                        CallbackSource.QUOTE,
                        perpOrder.info.trader,
                        perpOrder.marginAmount,
                        perpOrder.validatorAddress,
                        perpOrder.validationData
                    )
                )
            ),
            settlementData
        );
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
