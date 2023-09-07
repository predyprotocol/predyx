// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IExchange {
    error PairNotFound();

    error LockedBy(address locker);

    error CurrencyNotSettled();

    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    struct PairStatus {
        uint256 id;
        address pool;
        address quoteAsset;
        address baseAsset;
    }

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

    function updatePosition(uint256 pairId, bool isQuoteAsset, int256 delta)
        external;
    function take(bool isQuoteAsset, address to, uint256 amount) external;
    function settle(uint256 pairId, bool isQuoteAsset)
        external
        returns (uint256 paid);
}
