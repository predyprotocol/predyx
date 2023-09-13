// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestWithdraw is TestPool {
    function setUp() public override {
        TestPool.setUp();
    }

    // withdraw succeeds
    // withdraw fails if user balance is not enough
    // withdraw fails if WithdrawnAmountFallsShortOfMin
    // withdraw fails if utilization is high
    // withdraw fails if amount is 0
    // withdraw fails if pairId is 0
}
