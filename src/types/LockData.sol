// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/IPredyPool.sol";

library LockDataLibrary {
    struct LockData {
        address locker;
        int256 quoteDelta;
        int256 baseDelta;
        uint256 quoteReserve;
        uint256 baseReserve;
        uint256 pairId;
        uint256 vaultId;
    }

    function validateCurrencyDelta(LockData storage lockData) internal view {
        if (lockData.baseDelta != 0) {
            revert IPredyPool.CurrencyNotSettled();
        }
    }
}
