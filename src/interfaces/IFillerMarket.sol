// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IFillerMarket {
    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    struct SignedOrder {
        Order order;
        bytes sig;
    }

    struct Order {
        uint256 positionId;
        uint256 pairId;
        int256 tradeAmount;
        int256 tradeAmountSqrt;
        uint256 limitPrice;
        uint256 deadline;
        int256 marginAmount;
        uint256 marginRatio;
        uint256 nonce;
    }
}
