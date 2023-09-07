// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IAssetHooks {
    function compose(bytes memory data) external;
    function addDebt(bytes memory data, int256 averagePrice) external;
}
