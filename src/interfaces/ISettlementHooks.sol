// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface ISettlementHooks {
    function settlementCallback(
        bytes memory data,
        int256 quoteAmountDelta,
        int256 baseAmountDelta
    )
        external;
}
