// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "../../interfaces/IPredyPool.sol";
import "../../interfaces/ILendingPool.sol";
import "../../interfaces/IFillerMarket.sol";
import "../../interfaces/IOrderValidator.sol";
import "../../base/BaseMarket.sol";
import "../../libraries/orders/Permit2Lib.sol";
import "../../libraries/orders/ResolvedOrder.sol";
import "../../libraries/logic/LiquidationLogic.sol";
import "./GammaOrder.sol";
import "../../libraries/math/Math.sol";
import {PredyPoolQuoter} from "../../lens/PredyPoolQuoter.sol";

/**
 * @notice Gamma trade market contract
 */
contract GammaTradeMarket is IFillerMarket, BaseMarket {
    using ResolvedOrderLib for ResolvedOrder;
    using GammaOrderLib for GammaOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;
    using SafeTransferLib for ERC20;

    error HedgeTriggerNotMatched();

    struct UserPosition {
        address owner;
        uint256 vaultId;
        uint256 lastHedgedTime;
        uint256 hedgeInterval;
        uint256 lastHedgedSqrtPrice;
        uint256 sqrtPriceTrigger;
        uint64 maxSlippageTolerance;
    }

    struct CallbackData {
        address trader;
        int256 marginAmountUpdate;
    }

    // 0.1%
    uint256 private constant _MIN_SLIPPAGE = 1001000;
    // 20 minutes
    uint256 private constant _AUCTION_DURATION = 20 minutes;

    IPermit2 private immutable _permit2;

    mapping(address owner => mapping(uint256 pairId => UserPosition)) public userPositions;

    event Traded(address trader, uint256 vaultId);
    event Hedged(address owner, uint256 pairId, uint256 vaultId, uint256 sqrtPrice, int256 delta);

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

            ERC20(_getQuoteTokenAddress(tradeParams.pairId)).safeTransfer(callbackData.trader, uint256(vault.margin));
        } else {
            int256 marginAmountUpdate = callbackData.marginAmountUpdate;

            if (marginAmountUpdate > 0) {
                ERC20(_getQuoteTokenAddress(tradeParams.pairId)).safeTransfer(
                    address(_predyPool), uint256(marginAmountUpdate)
                );
            } else if (marginAmountUpdate < 0) {
                ILendingPool(address(_predyPool)).take(true, address(this), uint256(-marginAmountUpdate));

                ERC20(_getQuoteTokenAddress(tradeParams.pairId)).safeTransfer(
                    callbackData.trader, uint256(-marginAmountUpdate)
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
        GammaOrder memory gammaOrder = abi.decode(order.order, (GammaOrder));
        ResolvedOrder memory resolvedOrder = GammaOrderLib.resolve(gammaOrder, order.sig);

        require(_quoteTokenMap[gammaOrder.pairId] != address(0));
        // TODO: check gammaOrder.entryTokenAddress and _quoteTokenMap[gammaOrder.pairId]
        require(gammaOrder.entryTokenAddress == _quoteTokenMap[gammaOrder.pairId]);

        _verifyOrder(resolvedOrder);

        UserPosition storage userPosition = userPositions[gammaOrder.info.trader][gammaOrder.pairId];

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                gammaOrder.pairId,
                userPosition.vaultId,
                gammaOrder.tradeAmount,
                gammaOrder.tradeAmountSqrt,
                abi.encode(CallbackData(gammaOrder.info.trader, gammaOrder.marginAmount))
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
            userPosition.owner = gammaOrder.info.trader;
            userPosition.vaultId = tradeResult.vaultId;

            _predyPool.updateRecepient(tradeResult.vaultId, gammaOrder.info.trader);
        }

        userPosition.hedgeInterval = gammaOrder.hedgeInterval;
        userPosition.sqrtPriceTrigger = gammaOrder.sqrtPriceTrigger;
        require(gammaOrder.maxSlippageTolerance <= Bps.ONE);
        userPosition.maxSlippageTolerance = gammaOrder.maxSlippageTolerance + Bps.ONE;

        IGammaOrderValidator(gammaOrder.validatorAddress).validate(gammaOrder, tradeResult);

        emit Traded(gammaOrder.info.trader, tradeResult.vaultId);

        return tradeResult;
    }

    /**
     * @notice Executes delta hedging
     * @param owner owner address
     * @param pairId The id of pair
     * @param settlementData The route of settlement created by filler
     * @return tradeResult The result of trade
     * @dev Anyone can call this function
     */
    function execDeltaHedge(address owner, uint256 pairId, ISettlement.SettlementData memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        UserPosition storage userPosition = userPositions[owner][pairId];

        require(userPosition.vaultId > 0 && userPosition.owner == owner);

        DataType.Vault memory vault = _predyPool.getVault(userPosition.vaultId);

        uint256 sqrtPrice = _predyPool.getSqrtIndexPrice(vault.openPosition.pairId);

        int256 delta = _calculateDelta(sqrtPrice, vault.openPosition.sqrtPerp.amount, vault.openPosition.perp.amount);

        if (!_validateHedgeCondition(userPosition, sqrtPrice)) {
            revert HedgeTriggerNotMatched();
        }

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                vault.openPosition.pairId, userPosition.vaultId, -delta, 0, abi.encode(CallbackData(owner, 0))
            ),
            settlementData
        );

        LiquidationLogic.checkPrice(
            sqrtPrice,
            tradeResult,
            _calculateSlippageTolerance(
                userPosition.lastHedgedTime + userPosition.hedgeInterval,
                block.timestamp,
                userPosition.maxSlippageTolerance
            ),
            vault.openPosition.sqrtPerp.amount != 0
        );

        userPosition.lastHedgedSqrtPrice = sqrtPrice;
        userPosition.lastHedgedTime = block.timestamp;

        emit Hedged(owner, pairId, userPosition.vaultId, sqrtPrice, delta);
    }

    function _calculateDelta(uint256 _sqrtPrice, int256 _sqrtAmount, int256 perpAmount)
        internal
        pure
        returns (int256)
    {
        return perpAmount + _sqrtAmount * int256(Constants.Q96) / int256(_sqrtPrice);
    }

    function _validateHedgeCondition(UserPosition memory userPosition, uint256 sqrtIndexPrice)
        internal
        view
        returns (bool)
    {
        if (userPosition.lastHedgedTime + userPosition.hedgeInterval <= block.timestamp) {
            return true;
        }

        uint256 upperThreshold = userPosition.lastHedgedSqrtPrice * userPosition.sqrtPriceTrigger / 1e4;
        uint256 lowerThreshold = userPosition.lastHedgedSqrtPrice * 1e4 / userPosition.sqrtPriceTrigger;

        if (lowerThreshold >= sqrtIndexPrice) {
            return true;
        }

        if (upperThreshold <= sqrtIndexPrice) {
            return true;
        }

        return false;
    }

    function _calculateSlippageTolerance(uint256 startTime, uint256 currentTime, uint256 maxSlippageTolerance)
        internal
        pure
        returns (uint256)
    {
        if (currentTime <= startTime) {
            return _MIN_SLIPPAGE;
        }

        uint256 elapsed = (currentTime - startTime) * 1e4 / _AUCTION_DURATION;

        if (elapsed > 1e4) {
            return maxSlippageTolerance;
        }

        return (_MIN_SLIPPAGE + elapsed * (maxSlippageTolerance - _MIN_SLIPPAGE) / 1e4);
    }

    function _verifyOrder(ResolvedOrder memory order) internal {
        order.validate();

        _permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(address(this)),
            order.info.trader,
            order.hash,
            GammaOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }
}
