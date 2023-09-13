// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestRegisterPair is TestPool {
    function setUp() public override {
        TestPool.setUp();
    }

    // register pool succeeds
    // register fails if uniswap pool is invalid
    // register fails if fee ratio is invalid
}
