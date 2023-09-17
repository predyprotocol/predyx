// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import "./Perp.sol";

library DataType {
    struct Vault {
        uint256 id;
        address marginId;
        address owner;
        int256 margin;
        Perp.UserStatus openPosition;
    }

    struct RebalanceFeeGrowthCache {
        int256 stableGrowth;
        int256 underlyingGrowth;
    }
}
