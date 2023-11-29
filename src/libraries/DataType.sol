// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import {Perp} from "./Perp.sol";

library DataType {
    struct PairStatus {
        uint256 id;
        address marginId;
        address poolOwner;
        Perp.AssetPoolStatus quotePool;
        Perp.AssetPoolStatus basePool;
        Perp.AssetRiskParams riskParams;
        Perp.SqrtPerpAssetStatus sqrtAssetStatus;
        address priceFeed;
        bool isMarginZero;
        bool whitelistEnabled;
        uint8 feeRatio;
        uint256 lastUpdateTimestamp;
    }

    struct Vault {
        uint256 id;
        address marginId;
        address owner;
        address recipient;
        int256 margin;
        Perp.UserStatus openPosition;
    }

    struct RebalanceFeeGrowthCache {
        int256 stableGrowth;
        int256 underlyingGrowth;
    }
}
