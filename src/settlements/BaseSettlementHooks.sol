// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../interfaces/IExchange.sol";
import "../interfaces/ISettlementHooks.sol";

abstract contract BaseSettlementHooks is ISettlementHooks {
    IExchange exchange;

    constructor(IExchange _exchange) {
        exchange = _exchange;
    }

    function settlementCallback(
        bytes memory callbackData,
        int256 quoteAmountDelta,
        int256 baseAmountDelta
    )
        public
        virtual;
}
