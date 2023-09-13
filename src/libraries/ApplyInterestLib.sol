// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

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

    function applyInterestForVault(DataType.Vault memory _vault, mapping(uint256 => Perp.PairStatus) storage _pairs)
        internal
    {
        uint256 pairId = _vault.openPosition.pairId;

        applyInterestForToken(_pairs, pairId);
    }

    function applyInterestForToken(mapping(uint256 => Perp.PairStatus) storage _pairs, uint256 _pairId) internal {
        Perp.PairStatus storage pairStatus = _pairs[_pairId];

        Perp.updateFeeAndPremiumGrowth(_pairId, pairStatus.sqrtAssetStatus);

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

    function applyInterestForPoolStatus(
        Perp.AssetPoolStatus storage _poolStatus,
        uint256 _lastUpdateTimestamp,
        uint8 _fee
    ) internal returns (uint256 interestRate) {
        if (block.timestamp <= _lastUpdateTimestamp) {
            return 0;
        }

        // Gets utilization ratio
        uint256 utilizationRatio = _poolStatus.tokenStatus.getUtilizationRatio();

        if (utilizationRatio == 0) {
            return 0;
        }

        // Calculates interest rate
        interestRate = InterestRateModel.calculateInterestRate(_poolStatus.irmParams, utilizationRatio)
            * (block.timestamp - _lastUpdateTimestamp) / 365 days;

        // Update scaler
        uint256 totalProtocolFee = _poolStatus.tokenStatus.updateScaler(interestRate, _fee);

        _poolStatus.accumulatedProtocolRevenue += totalProtocolFee / 2;
        _poolStatus.accumulatedCreatorRevenue += totalProtocolFee / 2;
    }

    function emitInterestGrowthEvent(
        Perp.PairStatus memory _assetStatus,
        uint256 _interestRatioStable,
        uint256 _interestRatioUnderlying
    ) internal {
        emit InterestGrowthUpdated(
            _assetStatus.id,
            _assetStatus.quotePool.tokenStatus,
            _assetStatus.basePool.tokenStatus,
            _interestRatioStable,
            _interestRatioUnderlying
        );
    }
}
