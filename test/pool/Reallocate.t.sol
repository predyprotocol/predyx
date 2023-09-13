// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestReallocate is TestPool {
    function setUp() public override {
        TestPool.setUp();
    }

    // reallocate succeeds
    // reallocate succeeds if totalAmount is 0
    // reallocate fails if current tick is within safe range
}
