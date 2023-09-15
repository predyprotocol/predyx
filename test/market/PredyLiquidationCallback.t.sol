// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";

contract TestPredyLiquidationCallback is TestMarket {
    function setUp() public override {
        TestMarket.setUp();
    }

    // liquidate a filler market position
}
