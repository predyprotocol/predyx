// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@solmate/utils/FixedPointMathLib.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {IHooks} from "../../interfaces/IHooks.sol";
import {ApplyInterestLib} from "../ApplyInterestLib.sol";
import {DataType} from "../DataType.sol";
import {Perp} from "../Perp.sol";
import {PerpFee} from "../PerpFee.sol";
import {GlobalDataLibrary} from "../../types/GlobalData.sol";
import {LockDataLibrary} from "../../types/LockData.sol";

library TradeLogic {
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;
    using LockDataLibrary for LockDataLibrary.LockData;

    struct SwapStableResult {
        int256 amountPerp;
        int256 amountSqrtPerp;
        int256 fee;
    }

    function trade(
        GlobalDataLibrary.GlobalData storage globalData,
        uint256 pairId,
        IPredyPool.TradeParams memory tradeParams,
        bytes memory settlementData
    ) external returns (IPredyPool.TradeResult memory tradeResult) {
        Perp.PairStatus storage pairStatus = globalData.pairs[pairId];
        Perp.UserStatus storage openPosition = globalData.vaults[tradeParams.vaultId].openPosition;

        // update interest growth
        ApplyInterestLib.applyInterestForToken(globalData.pairs, pairId);

        // update rebalance fee growth
        Perp.updateRebalanceFeeGrowth(pairStatus, pairStatus.sqrtAssetStatus);

        // settle user balance and fee
        (int256 underlyingFee, int256 stableFee) =
            _settleUserBalanceAndFee(pairStatus, globalData.rebalanceFeeGrowthCache, openPosition);

        // calculate required token amounts
        (int256 underlyingAmountForSqrt, int256 stableAmountForSqrt) = Perp.computeRequiredAmounts(
            pairStatus.sqrtAssetStatus, pairStatus.isMarginZero, openPosition, tradeParams.tradeAmountSqrt
        );

        // swap tokens
        SwapStableResult memory swapResult = _swap(
            globalData,
            pairId,
            SwapStableResult(-tradeParams.tradeAmount, underlyingAmountForSqrt, underlyingFee),
            settlementData
        );

        // add asset or debt
        tradeResult.payoff = Perp.updatePosition(
            pairStatus,
            openPosition,
            Perp.UpdatePerpParams(tradeParams.tradeAmount, swapResult.amountPerp),
            Perp.UpdateSqrtPerpParams(tradeParams.tradeAmountSqrt, swapResult.amountSqrtPerp + stableAmountForSqrt)
        );

        // round up or down payoff and fee
        tradeResult.payoff.perpPayoff = _roundAndAddToProtocolFee(pairStatus, tradeResult.payoff.perpPayoff, 4);
        tradeResult.payoff.sqrtPayoff = _roundAndAddToProtocolFee(pairStatus, tradeResult.payoff.sqrtPayoff, 4);
        tradeResult.fee = _roundAndAddToProtocolFee(pairStatus, stableFee + swapResult.fee, 4);

        // check vault is safe
    }

    function _swap(
        GlobalDataLibrary.GlobalData storage globalData,
        uint256 pairId,
        SwapStableResult memory swapParams,
        bytes memory settlementData
    ) internal returns (SwapStableResult memory) {
        int256 totalBaseAmount = swapParams.amountPerp + swapParams.amountSqrtPerp + swapParams.fee;

        globalData.initializeLock(pairId, msg.sender, totalBaseAmount);

        IHooks(msg.sender).predySettlementCallback(settlementData, totalBaseAmount);

        int256 totalQuoteAmount = globalData.lockData.quoteDelta;

        globalData.lockData.validateCurrencyDelta();
        delete globalData.lockData;

        return _divToStable(swapParams, totalBaseAmount, totalQuoteAmount, totalQuoteAmount);
    }

    function _divToStable(
        SwapStableResult memory swapParams,
        int256 amountUnderlying,
        int256 amountStable,
        int256 totalAmountStable
    ) internal pure returns (SwapStableResult memory swapResult) {
        swapResult.amountPerp = amountStable * swapParams.amountPerp / amountUnderlying;
        swapResult.amountSqrtPerp = amountStable * swapParams.amountSqrtPerp / amountUnderlying;
        swapResult.fee = totalAmountStable - swapResult.amountPerp - swapResult.amountSqrtPerp;
    }

    function _settleUserBalanceAndFee(
        Perp.PairStatus storage _pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage rebalanceFeeGrowthCache,
        Perp.UserStatus storage _userStatus
    ) internal returns (int256 underlyingFee, int256 stableFee) {
        (underlyingFee, stableFee) = PerpFee.settleUserFee(_pairStatus, rebalanceFeeGrowthCache, _userStatus);

        Perp.settleUserBalance(_pairStatus, _userStatus);
    }

    function _roundAndAddToProtocolFee(Perp.PairStatus storage _pairStatus, int256 _amount, uint8 _marginRoundedDecimal)
        internal
        returns (int256)
    {
        int256 rounded = _roundMargin(_amount, 10 ** _marginRoundedDecimal);

        if (_amount > rounded) {
            _pairStatus.quotePool.accumulatedProtocolRevenue += uint256(_amount - rounded);
        }

        return rounded;
    }

    function _roundMargin(int256 _amount, uint256 _roundedDecimals) internal pure returns (int256) {
        if (_amount > 0) {
            return int256(FixedPointMathLib.mulDivDown(uint256(_amount), 1, _roundedDecimals) * _roundedDecimals);
        } else {
            return -int256(FixedPointMathLib.mulDivUp(uint256(-_amount), 1, _roundedDecimals) * _roundedDecimals);
        }
    }
}
