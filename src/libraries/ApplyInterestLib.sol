// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import "./Perp.sol";
import "./ScaledAsset.sol";
import "./DataType.sol";

library ApplyInterestLib {
    using ScaledAsset for ScaledAsset.AssetStatus;

    event InterestGrowthUpdated(
        uint256 pairId,
        ScaledAsset.AssetStatus stableStatus,
        ScaledAsset.AssetStatus underlyingStatus,
        uint256 interestRateStable,
        uint256 interestRateUnderlying
    );

    function applyInterestForToken(mapping(uint256 => DataType.PairStatus) storage pairs, uint256 pairId) internal {
        DataType.PairStatus storage pairStatus = pairs[pairId];

        if (pairStatus.lastUpdateTimestamp >= block.timestamp) {
            return;
        }

        Perp.updateFeeAndPremiumGrowth(pairId, pairStatus.sqrtAssetStatus);

        uint256 interestRateStable =
            applyInterestForPoolStatus(pairStatus.quotePool, pairStatus.lastUpdateTimestamp, pairStatus.feeRatio);

        uint256 interestRateUnderlying =
            applyInterestForPoolStatus(pairStatus.basePool, pairStatus.lastUpdateTimestamp, pairStatus.feeRatio);

        // Update last update timestamp
        pairStatus.lastUpdateTimestamp = block.timestamp;

        if (interestRateStable > 0 || interestRateUnderlying > 0) {
            emitInterestGrowthEvent(pairStatus, interestRateStable, interestRateUnderlying);
        }
    }

    function applyInterestForPoolStatus(Perp.AssetPoolStatus storage poolStatus, uint256 lastUpdateTimestamp, uint8 fee)
        internal
        returns (uint256 interestRate)
    {
        if (block.timestamp <= lastUpdateTimestamp) {
            return 0;
        }

        // Gets utilization ratio
        uint256 utilizationRatio = poolStatus.tokenStatus.getUtilizationRatio();

        if (utilizationRatio == 0) {
            return 0;
        }

        // Calculates interest rate
        interestRate = InterestRateModel.calculateInterestRate(poolStatus.irmParams, utilizationRatio)
            * (block.timestamp - lastUpdateTimestamp) / 365 days;

        // Update scaler
        uint256 totalProtocolFee = poolStatus.tokenStatus.updateScaler(interestRate, fee);

        poolStatus.accumulatedProtocolRevenue += totalProtocolFee / 2;
        poolStatus.accumulatedCreatorRevenue += totalProtocolFee / 2;
    }

    function emitInterestGrowthEvent(
        DataType.PairStatus memory assetStatus,
        uint256 interestRatioStable,
        uint256 interestRatioUnderlying
    ) internal {
        emit InterestGrowthUpdated(
            assetStatus.id,
            assetStatus.quotePool.tokenStatus,
            assetStatus.basePool.tokenStatus,
            interestRatioStable,
            interestRatioUnderlying
        );
    }
}
