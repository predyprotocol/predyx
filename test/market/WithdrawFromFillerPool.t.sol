// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestWithdrawFromFillerPool is TestMarket {

    function setUp() public override {
        TestMarket.setUp();
    }

    // withdraw succeeds
    // withdraw succeeds with borrow fee
    // withdraw fails if there is no available pool balance
}
