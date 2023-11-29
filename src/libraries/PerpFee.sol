// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./PairLib.sol";
import "./Perp.sol";
import "./DataType.sol";
import "./Constants.sol";
import {ScaledAsset} from "./ScaledAsset.sol";
import {Math} from "./math/Math.sol";

library PerpFee {
    using ScaledAsset for ScaledAsset.AssetStatus;
    using SafeCast for uint256;

    function computeUserFee(
        DataType.PairStatus memory assetStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage rebalanceFeeGrowthCache,
        Perp.UserStatus memory userStatus
    ) internal view returns (int256 unrealizedFeeUnderlying, int256 unrealizedFeeStable) {
        unrealizedFeeUnderlying = assetStatus.basePool.tokenStatus.computeUserFee(userStatus.underlying);
        unrealizedFeeStable = assetStatus.quotePool.tokenStatus.computeUserFee(userStatus.stable);

        {
            (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) = computeRebalanceEntryFee(
                assetStatus.id, assetStatus.sqrtAssetStatus, rebalanceFeeGrowthCache, userStatus
            );
            unrealizedFeeUnderlying += rebalanceFeeUnderlying;
            unrealizedFeeStable += rebalanceFeeStable;
        }

        {
            (int256 feeUnderlying, int256 feeStable) = computePremium(assetStatus, userStatus.sqrtPerp);
            unrealizedFeeUnderlying += feeUnderlying;
            unrealizedFeeStable += feeStable;
        }
    }

    function settleUserFee(
        DataType.PairStatus storage assetStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage rebalanceFeeGrowthCache,
        Perp.UserStatus storage userStatus
    ) internal returns (int256 totalFeeUnderlying, int256 totalFeeStable) {
        // settle asset interest
        totalFeeUnderlying = assetStatus.basePool.tokenStatus.settleUserFee(userStatus.underlying);
        totalFeeStable = assetStatus.quotePool.tokenStatus.settleUserFee(userStatus.stable);

        // settle rebalance interest
        (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) =
            settleRebalanceEntryFee(assetStatus.id, assetStatus.sqrtAssetStatus, rebalanceFeeGrowthCache, userStatus);

        // settle trade fee
        (int256 feeUnderlying, int256 feeStable) = settlePremium(assetStatus, userStatus.sqrtPerp);

        totalFeeStable += feeStable + rebalanceFeeStable;
        totalFeeUnderlying += feeUnderlying + rebalanceFeeUnderlying;
    }

    // Trade fee and premium

    function computePremium(DataType.PairStatus memory baseAssetStatus, Perp.SqrtPositionStatus memory sqrtPerp)
        internal
        pure
        returns (int256 feeUnderlying, int256 feeStable)
    {
        uint256 growthDiff0;
        uint256 growthDiff1;

        if (sqrtPerp.amount > 0) {
            growthDiff0 = baseAssetStatus.sqrtAssetStatus.fee0Growth - sqrtPerp.entryTradeFee0;
            growthDiff1 = baseAssetStatus.sqrtAssetStatus.fee1Growth - sqrtPerp.entryTradeFee1;
        } else if (sqrtPerp.amount < 0) {
            growthDiff0 = baseAssetStatus.sqrtAssetStatus.borrowPremium0Growth - sqrtPerp.entryTradeFee0;
            growthDiff1 = baseAssetStatus.sqrtAssetStatus.borrowPremium1Growth - sqrtPerp.entryTradeFee1;
        } else {
            return (feeUnderlying, feeStable);
        }

        int256 fee0 = Math.mulDivDownInt256(sqrtPerp.amount, growthDiff0, Constants.Q128);
        int256 fee1 = Math.mulDivDownInt256(sqrtPerp.amount, growthDiff1, Constants.Q128);

        if (baseAssetStatus.isMarginZero) {
            feeStable = fee0;
            feeUnderlying = fee1;
        } else {
            feeUnderlying = fee0;
            feeStable = fee1;
        }
    }

    function settlePremium(DataType.PairStatus memory baseAssetStatus, Perp.SqrtPositionStatus storage sqrtPerp)
        internal
        returns (int256 feeUnderlying, int256 feeStable)
    {
        (feeUnderlying, feeStable) = computePremium(baseAssetStatus, sqrtPerp);

        if (sqrtPerp.amount > 0) {
            sqrtPerp.entryTradeFee0 = baseAssetStatus.sqrtAssetStatus.fee0Growth;
            sqrtPerp.entryTradeFee1 = baseAssetStatus.sqrtAssetStatus.fee1Growth;
        } else if (sqrtPerp.amount < 0) {
            sqrtPerp.entryTradeFee0 = baseAssetStatus.sqrtAssetStatus.borrowPremium0Growth;
            sqrtPerp.entryTradeFee1 = baseAssetStatus.sqrtAssetStatus.borrowPremium1Growth;
        }
    }

    // Rebalance fee

    function computeRebalanceEntryFee(
        uint256 pairId,
        Perp.SqrtPerpAssetStatus memory assetStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage rebalanceFeeGrowthCache,
        Perp.UserStatus memory userStatus
    ) internal view returns (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) {
        if (userStatus.sqrtPerp.amount != 0 && userStatus.lastNumRebalance < assetStatus.numRebalance) {
            uint256 rebalanceId = PairLib.getRebalanceCacheId(pairId, userStatus.lastNumRebalance);

            uint256 rebalanceAmount = Math.abs(userStatus.sqrtPerp.amount);

            rebalanceFeeUnderlying = Math.mulDivDownInt256(
                assetStatus.rebalanceFeeGrowthUnderlying - rebalanceFeeGrowthCache[rebalanceId].underlyingGrowth,
                rebalanceAmount,
                Constants.ONE
            );
            rebalanceFeeStable = Math.mulDivDownInt256(
                assetStatus.rebalanceFeeGrowthStable - rebalanceFeeGrowthCache[rebalanceId].stableGrowth,
                rebalanceAmount,
                Constants.ONE
            );
        }
    }

    function settleRebalanceEntryFee(
        uint256 pairId,
        Perp.SqrtPerpAssetStatus storage assetStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage rebalanceFeeGrowthCache,
        Perp.UserStatus storage userStatus
    ) internal returns (int256 rebalanceFeeUnderlying, int256 rebalanceFeeStable) {
        if (userStatus.sqrtPerp.amount != 0 && userStatus.lastNumRebalance < assetStatus.numRebalance) {
            (rebalanceFeeUnderlying, rebalanceFeeStable) =
                computeRebalanceEntryFee(pairId, assetStatus, rebalanceFeeGrowthCache, userStatus);

            uint256 rebalanceAmount = Math.abs(userStatus.sqrtPerp.amount);

            assetStatus.lastRebalanceTotalSquartAmount -= rebalanceAmount;
        }

        userStatus.lastNumRebalance = assetStatus.numRebalance;
    }
}
