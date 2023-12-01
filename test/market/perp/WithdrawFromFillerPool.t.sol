// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";

contract TestWithdrawFromFillerPool is TestPerpMarket {
    function setUp() public override {
        TestPerpMarket.setUp();
    }

    // withdraw succeeds
    // withdraw succeeds with borrow fee
    // withdraw fails if there is no available pool balance
}