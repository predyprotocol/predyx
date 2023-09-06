// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./IPoolManager.sol";

interface IHooks {
    function afterTrade(IPoolManager.SignedOrder memory order) external;
}

interface ISupplyHook {
    function lockAquired(bytes memory callbackData) external;
}
