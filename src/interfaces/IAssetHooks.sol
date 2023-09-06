// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IAssetHooks {
    function compose(bytes memory data) external;
    function addDebt(bytes memory data, int256 averagePrice) external;
}

interface ISettlementHook {
    function settlementCallback(bytes memory data, int256 quoteAmountDelta, int256 baseAmountDelta) external;
}
