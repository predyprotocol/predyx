// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";

contract TestPerpDepositToFillerPool is TestPerpMarket {
    function setUp() public override {
        TestPerpMarket.setUp();
    }

    // deposit succeeds
    // deposit fails if caller has no balance
}
