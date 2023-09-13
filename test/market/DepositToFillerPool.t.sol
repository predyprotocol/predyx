// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestDepositToFillerPool is TestMarket {
    function setUp() public override {
        TestMarket.setUp();
    }

    // deposit succeeds
    // deposit fails if caller has no balance
}
