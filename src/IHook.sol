// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./IPoolManager.sol";

interface IHook {
    function lockAquired(
        IPoolManager.SignedOrder[] memory orders
    ) external;

}
