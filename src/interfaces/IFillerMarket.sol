// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IFillerMarket {
    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    struct SignedOrder {
        bytes order;
        bytes sig;
    }
}
