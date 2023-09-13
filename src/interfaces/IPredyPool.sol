// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IPredyPool {
    error PairNotFound();

    error LockedBy(address locker);

    error CurrencyNotSettled();

    error SupplyAmountExceedsMax();

    error InvalidAmount();

    struct PairStatus {
        uint256 id;
        address marginId;
        AssetPoolStatus stablePool;
        AssetPoolStatus underlyingPool;
        AssetRiskParams riskParams;
        Perp.SqrtPerpAssetStatus sqrtAssetStatus;
        bool isMarginZero;
        bool isIsolatedMode;
        uint256 lastUpdateTimestamp;
    }

    struct AssetPoolStatus {
        address token;
        address supplyTokenAddress;
        ScaledAsset.TokenStatus tokenStatus;
        InterestRateModel.IRMParams irmParams;
    }

    struct AssetRiskParams {
        uint256 riskRatio;
        int24 rangeSize;
        int24 rebalanceThreshold;
    }

    struct LockData {
        address locker;
        uint256 deltaCount;
        uint256 pairId;
        uint256 vaultId;
    }

    struct TradeParams {
        uint256 pairId;
        uint256 vaultId;
        int256 tradeAmount;
        int256 tradeAmountSqrt;
        bytes extraData;
    }

    struct TradeResult {
        Payoff payoff;
        int256 fee;
        int256 minDeposit;
    }

    struct Payoff {
        int256 perpEntryUpdate;
        int256 sqrtEntryUpdate;
        int256 sqrtRebalanceEntryUpdateUnderlying;
        int256 sqrtRebalanceEntryUpdateStable;
        int256 perpPayoff;
        int256 sqrtPayoff;
    }

    struct VaultStatus {
        uint256 id;
        int256 margin;
    }

}
