// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPredyPool} from "../interfaces/IPredyPool.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {ISettlement} from "../interfaces/ISettlement.sol";
import {Constants} from "./Constants.sol";
import {DataType} from "./DataType.sol";
import {Perp} from "./Perp.sol";
import {PerpFee} from "./PerpFee.sol";
import {GlobalDataLibrary} from "../types/GlobalData.sol";
import {LockDataLibrary} from "../types/LockData.sol";
import {PositionCalculator} from "./PositionCalculator.sol";
import {Math} from "./math/Math.sol";
import {UniHelper} from "./UniHelper.sol";

library Trade {
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;

    struct SwapStableResult {
        int256 amountPerp;
        int256 amountSqrtPerp;
        int256 fee;
        int256 averagePrice;
    }

    function trade(
        GlobalDataLibrary.GlobalData storage globalData,
        IPredyPool.TradeParams memory tradeParams,
        ISettlement.SettlementData memory settlementData
    ) external returns (IPredyPool.TradeResult memory tradeResult) {
        DataType.PairStatus storage pairStatus = globalData.pairs[tradeParams.pairId];
        Perp.UserStatus storage openPosition = globalData.vaults[tradeParams.vaultId].openPosition;

        // update rebalance interest growth
        Perp.updateRebalanceInterestGrowth(pairStatus, pairStatus.sqrtAssetStatus);

        // settle user balance and fee
        (int256 underlyingFee, int256 stableFee) =
            settleUserBalanceAndFee(pairStatus, globalData.rebalanceFeeGrowthCache, openPosition);

        // calculate required token amounts
        (int256 underlyingAmountForSqrt, int256 stableAmountForSqrt) = Perp.computeRequiredAmounts(
            pairStatus.sqrtAssetStatus, pairStatus.isMarginZero, openPosition, tradeParams.tradeAmountSqrt
        );

        tradeResult.sqrtPrice = getSqrtPrice(pairStatus.sqrtAssetStatus.uniswapPool, pairStatus.isMarginZero);

        // swap tokens

        SwapStableResult memory swapResult = swap(
            globalData,
            tradeParams.pairId,
            SwapStableResult(-tradeParams.tradeAmount, underlyingAmountForSqrt, underlyingFee, 0),
            settlementData,
            tradeResult.sqrtPrice
        );

        tradeResult.averagePrice = swapResult.averagePrice;

        // add asset or debt
        tradeResult.payoff = Perp.updatePosition(
            pairStatus,
            openPosition,
            Perp.UpdatePerpParams(tradeParams.tradeAmount, swapResult.amountPerp),
            Perp.UpdateSqrtPerpParams(tradeParams.tradeAmountSqrt, swapResult.amountSqrtPerp + stableAmountForSqrt)
        );

        tradeResult.fee = stableFee + swapResult.fee;
        tradeResult.vaultId = tradeParams.vaultId;
    }

    function swap(
        GlobalDataLibrary.GlobalData storage globalData,
        uint256 pairId,
        SwapStableResult memory swapParams,
        ISettlement.SettlementData memory settlementData,
        uint256 sqrtPrice
    ) internal returns (SwapStableResult memory) {
        int256 totalBaseAmount = swapParams.amountPerp + swapParams.amountSqrtPerp + swapParams.fee;

        if (totalBaseAmount == 0) {
            int256 amountStable = int256(calculateStableAmount(sqrtPrice, 1e18));

            return divToStable(swapParams, int256(1e18), amountStable, 0);
        }

        globalData.initializeLock(pairId, settlementData.settlementContractAddress);

        ISettlement(settlementData.settlementContractAddress).predySettlementCallback(
            settlementData.encodedData, totalBaseAmount
        );

        int256 totalQuoteAmount = globalData.settle(true);

        if (globalData.settle(false) != -totalBaseAmount) {
            revert IPredyPool.BaseTokenNotSettled();
        }

        // totalQuoteAmount must be non-zero
        if (totalQuoteAmount * totalBaseAmount <= 0) {
            revert IPredyPool.QuoteTokenNotSettled();
        }

        delete globalData.lockData;

        return divToStable(swapParams, totalBaseAmount, totalQuoteAmount, totalQuoteAmount);
    }

    function getSqrtPrice(address uniswapPoolAddress, bool isMarginZero) internal view returns (uint256 sqrtPriceX96) {
        return UniHelper.convertSqrtPrice(UniHelper.getSqrtPrice(uniswapPoolAddress), isMarginZero);
    }

    function calculateStableAmount(uint256 currentSqrtPrice, uint256 baseAmount) internal pure returns (uint256) {
        uint256 quoteAmount = (currentSqrtPrice * baseAmount) >> Constants.RESOLUTION;

        return (quoteAmount * currentSqrtPrice) >> Constants.RESOLUTION;
    }

    function divToStable(
        SwapStableResult memory swapParams,
        int256 amountUnderlying,
        int256 amountStable,
        int256 totalAmountStable
    ) internal pure returns (SwapStableResult memory swapResult) {
        swapResult.amountPerp = amountStable * swapParams.amountPerp / amountUnderlying;
        swapResult.amountSqrtPerp = amountStable * swapParams.amountSqrtPerp / amountUnderlying;
        swapResult.fee = totalAmountStable - swapResult.amountPerp - swapResult.amountSqrtPerp;

        swapResult.averagePrice = totalAmountStable * int256(Constants.Q96) / int256(Math.abs(amountUnderlying));
    }

    function settleUserBalanceAndFee(
        DataType.PairStatus storage _pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage rebalanceFeeGrowthCache,
        Perp.UserStatus storage _userStatus
    ) internal returns (int256 underlyingFee, int256 stableFee) {
        (underlyingFee, stableFee) = PerpFee.settleUserFee(_pairStatus, rebalanceFeeGrowthCache, _userStatus);

        Perp.settleUserBalance(_pairStatus, _userStatus);
    }
}
