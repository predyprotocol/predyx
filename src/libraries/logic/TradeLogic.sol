// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IPredyPool.sol";
import "../../interfaces/IHooks.sol";
import "../../types/GlobalData.sol";
import "../PerpFee.sol";

library TradeLogic {
    function trade(
        GlobalDataLibrary.GlobalData storage globalData,
        uint256 pairId,
        IPredyPool.TradeParams memory tradeParams,
        bytes memory settlementData
    ) external returns (IPredyPool.TradeResult memory tradeResult) {
        Perp.PairStatus storage pairStatus = globalData.pairs[pairId];
        Perp.UserStatus storage openPosition = globalData.vaults[tradeParams.vaultId].openPosition;

        Perp.updateRebalanceFeeGrowth(pairStatus, pairStatus.sqrtAssetStatus);

        // pre trade
        (int256 underlyingFee, int256 stableFee) =
            settleUserBalanceAndFee(pairStatus, globalData.rebalanceFeeGrowthCache, openPosition);

        (int256 underlyingAmountForSqrt, int256 stableAmountForSqrt) = Perp.computeRequiredAmounts(
            pairStatus.sqrtAssetStatus, pairStatus.isMarginZero, openPosition, tradeParams.tradeAmountSqrt
        );

        // swap
        SwapStableResult memory swapResult = swap(
            globalData,
            pairId,
            SwapStableResult(-tradeParams.tradeAmount, underlyingAmountForSqrt, underlyingFee),
            settlementData
        );

        // post trade
        // update position
        tradeResult.payoff = Perp.updatePosition(
            pairStatus,
            openPosition,
            Perp.UpdatePerpParams(tradeParams.tradeAmount, swapResult.amountPerp),
            Perp.UpdateSqrtPerpParams(tradeParams.tradeAmountSqrt, swapResult.amountSqrtPerp + stableAmountForSqrt)
        );

        tradeResult.payoff.perpPayoff = roundAndAddToProtocolFee(pairStatus, tradeResult.payoff.perpPayoff, 4);
        tradeResult.payoff.sqrtPayoff = roundAndAddToProtocolFee(pairStatus, tradeResult.payoff.sqrtPayoff, 4);

        tradeResult.fee = roundAndAddToProtocolFee(pairStatus, stableFee + swapResult.fee, 4);

        // check vault is safe
    }

    struct SwapStableResult {
        int256 amountPerp;
        int256 amountSqrtPerp;
        int256 fee;
    }

    function swap(
        GlobalDataLibrary.GlobalData storage globalData,
        uint256 pairId,
        SwapStableResult memory swapParams,
        bytes memory settlementData
    ) internal returns (SwapStableResult memory) {
        globalData.lockData.quoteReserve = IERC20(globalData.pairs[pairId].quotePool.token).balanceOf(address(this));
        globalData.lockData.baseReserve = IERC20(globalData.pairs[pairId].basePool.token).balanceOf(address(this));
        globalData.lockData.locker = msg.sender;

        int256 totalBaseAmount = swapParams.amountPerp + swapParams.amountSqrtPerp + swapParams.fee;

        IHooks(msg.sender).predySettlementCallback(settlementData, totalBaseAmount);

        int256 totalQuoteAmount = globalData.lockData.quoteDelta;

        GlobalDataLibrary.validateCurrencyDelta(globalData.lockData);
        globalData.lockData.locker = address(0);

        return divToStable(swapParams, totalBaseAmount, totalQuoteAmount, totalQuoteAmount);
    }

    function divToStable(
        SwapStableResult memory _swapParams,
        int256 _amountUnderlying,
        int256 _amountStable,
        int256 _totalAmountStable
    ) internal pure returns (SwapStableResult memory swapResult) {
        // TODO: calculate trade price
        swapResult.amountPerp = _amountStable * _swapParams.amountPerp / _amountUnderlying;
        swapResult.amountSqrtPerp = _amountStable * _swapParams.amountSqrtPerp / _amountUnderlying;
        swapResult.fee = _totalAmountStable - swapResult.amountPerp - swapResult.amountSqrtPerp;
    }

    function settleUserBalanceAndFee(
        Perp.PairStatus storage _pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage rebalanceFeeGrowthCache,
        Perp.UserStatus storage _userStatus
    ) internal returns (int256 underlyingFee, int256 stableFee) {
        (underlyingFee, stableFee) = PerpFee.settleUserFee(_pairStatus, rebalanceFeeGrowthCache, _userStatus);

        Perp.settleUserBalance(_pairStatus, _userStatus);
    }

    function roundAndAddToProtocolFee(Perp.PairStatus storage _pairStatus, int256 _amount, uint8 _marginRoundedDecimal)
        internal
        returns (int256)
    {
        int256 rounded = roundMargin(_amount, 10 ** _marginRoundedDecimal);

        if (_amount > rounded) {
            _pairStatus.quotePool.accumulatedProtocolRevenue += uint256(_amount - rounded);
        }

        return rounded;
    }

    function roundMargin(int256 _amount, uint256 _roundedDecimals) internal pure returns (int256) {
        if (_amount > 0) {
            return int256(FixedPointMathLib.mulDivDown(uint256(_amount), 1, _roundedDecimals) * _roundedDecimals);
        } else {
            return -int256(FixedPointMathLib.mulDivUp(uint256(-_amount), 1, _roundedDecimals) * _roundedDecimals);
        }
    }
}
