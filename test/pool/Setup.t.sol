// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/PredyPool.sol";
import "forge-std/Test.sol";

contract TestPool is Test {

    PredyPool predyPool;

    function setUp() public virtual {
        predyPool = new PredyPool();
    }
}
