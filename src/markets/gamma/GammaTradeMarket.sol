// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {ReentrancyGuard} from "@solmate/src/utils/ReentrancyGuard.sol";
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
contract GammaTradeMarket is IFillerMarket, BaseMarket, ReentrancyGuard {
    using ResolvedOrderLib for ResolvedOrder;
    using GammaOrderLib for GammaOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;
    using SafeTransferLib for ERC20;

    error TooSmallHedgeInterval();
    error HedgeTriggerNotMatched();

    struct UserPosition {
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
    // The duration of dutch auction is 20 minutes
    uint256 private constant _AUCTION_DURATION = 20 minutes;

    IPermit2 private immutable _permit2;

    mapping(address owner => mapping(uint256 pairId => UserPosition)) public userPositions;

    event GammaPositionTraded(
        address trader,
        uint256 vaultId,
        uint256 hedgeInterval,
        uint256 sqrtPriceTrigger,
        IPredyPool.Payoff payoff,
        int256 fee,
        int256 marginAmount
    );
    event GammaPositionHedged(
        address owner,
        uint256 pairId,
        uint256 vaultId,
        uint256 sqrtPrice,
        int256 delta,
        IPredyPool.Payoff payoff,
        int256 fee
    );

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
        nonReentrant
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        GammaOrder memory gammaOrder = abi.decode(order.order, (GammaOrder));
        ResolvedOrder memory resolvedOrder = GammaOrderLib.resolve(gammaOrder, order.sig);

        validateQuoteTokenAddress(gammaOrder.pairId, gammaOrder.entryTokenAddress);

        _verifyOrder(resolvedOrder);

        UserPosition storage userPosition = userPositions[gammaOrder.info.trader][gammaOrder.pairId];

        _saveUserPosition(
            userPosition, gammaOrder.hedgeInterval, gammaOrder.sqrtPriceTrigger, gammaOrder.maxSlippageTolerance
        );

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
            userPosition.vaultId = tradeResult.vaultId;

            _predyPool.updateRecepient(tradeResult.vaultId, gammaOrder.info.trader);
        }

        IGammaOrderValidator(gammaOrder.validatorAddress).validate(gammaOrder, tradeResult);

        emit GammaPositionTraded(
            gammaOrder.info.trader,
            tradeResult.vaultId,
            gammaOrder.hedgeInterval,
            gammaOrder.sqrtPriceTrigger,
            tradeResult.payoff,
            tradeResult.fee,
            gammaOrder.marginAmount
        );

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
        nonReentrant
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        UserPosition storage userPosition = userPositions[owner][pairId];

        require(userPosition.vaultId > 0);

        DataType.Vault memory vault = _predyPool.getVault(userPosition.vaultId);

        uint256 sqrtPrice = _predyPool.getSqrtIndexPrice(vault.openPosition.pairId);

        int256 delta = _calculateDelta(sqrtPrice, vault.openPosition.sqrtPerp.amount, vault.openPosition.perp.amount);

        if (!_validateHedgeCondition(userPosition, sqrtPrice)) {
            revert HedgeTriggerNotMatched();
        }

        uint256 hedgeAuctionStartTime = userPosition.lastHedgedTime + userPosition.hedgeInterval;

        userPosition.lastHedgedSqrtPrice = sqrtPrice;
        userPosition.lastHedgedTime = block.timestamp;

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                vault.openPosition.pairId, userPosition.vaultId, -delta, 0, abi.encode(CallbackData(owner, 0))
            ),
            settlementData
        );

        LiquidationLogic.checkPrice(
            sqrtPrice,
            tradeResult,
            _calculateSlippageTolerance(hedgeAuctionStartTime, block.timestamp, userPosition.maxSlippageTolerance),
            vault.openPosition.sqrtPerp.amount != 0
        );

        emit GammaPositionHedged(
            owner, pairId, userPosition.vaultId, sqrtPrice, delta, tradeResult.payoff, tradeResult.fee
        );
    }

    function _saveUserPosition(
        UserPosition storage userPosition,
        uint256 hedgeInterval,
        uint256 sqrtPriceTrigger,
        uint64 maxSlippageTolerance
    ) internal {
        if (2 hours > hedgeInterval) {
            revert TooSmallHedgeInterval();
        }

        require(maxSlippageTolerance <= Bps.ONE && maxSlippageTolerance + Bps.ONE >= _MIN_SLIPPAGE);

        userPosition.hedgeInterval = hedgeInterval;
        userPosition.sqrtPriceTrigger = sqrtPriceTrigger;
        userPosition.maxSlippageTolerance = maxSlippageTolerance + Bps.ONE;
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

        // if sqrtPriceTrigger is 0, it means that the user doesn't want to use this feature
        if (userPosition.sqrtPriceTrigger == 0) {
            return false;
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
