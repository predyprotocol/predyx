// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IPoolManager {
    error PairNotFound();

    error LockedBy(address locker);

    error CurrencyNotSettled();

    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    struct SignedOrder {
        uint256 pairId;
        uint256 vaultId;
        int256 tradeAmount;
        int256 limitPrice;
        uint256 deadline;
    }

    struct LockData {
        address locker;
        uint256 deltaCount;
        uint256 pairId;
        uint256 vaultId;
    }
}
