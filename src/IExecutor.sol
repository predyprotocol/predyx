// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./IPoolManager.sol";

interface IExecutor {
    function settleCallback(
        bytes memory callbackData
    ) external;

}
