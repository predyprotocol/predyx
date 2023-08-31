// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IPoolManager {
    error LockedBy(address locker);

    error CurrencyNotSettled();
    
    struct SignedOrder {
        uint256 vaultId;
        bytes data;
        // uint256 tradeAmount;
        // uint256 limitPrice;
        uint256 deadline;
    }

    struct LockData {
        address locker;
        uint256 deltaCount;
    }
}
