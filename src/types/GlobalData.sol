// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "../interfaces/IPredyPool.sol";
import "../libraries/DataType.sol";

library GlobalDataLibrary {
    struct LockData {
        address locker;
        int256 quoteDelta;
        int256 baseDelta;
        uint256 quoteReserve;
        uint256 baseReserve;
        uint256 pairId;
        uint256 vaultId;
    }

    struct GlobalData {
        uint256 pairsCount;
        uint256 vaultCount;
        address uniswapFactory;
        mapping(uint256 => Perp.PairStatus) pairs;
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) rebalanceFeeGrowthCache;
        mapping(uint256 => DataType.Vault) vaults;
        LockData lockData;
    }

    function validate(GlobalDataLibrary.GlobalData storage globalData, uint256 pairId) internal view {
        if (pairId <= 0 || globalData.pairsCount <= pairId) revert IPredyPool.InvalidPairId();
    }

    function validateCurrencyDelta(GlobalDataLibrary.LockData storage lockData) internal {
        if (lockData.baseDelta != 0) {
            revert IPredyPool.CurrencyNotSettled();
        }
    }
}
