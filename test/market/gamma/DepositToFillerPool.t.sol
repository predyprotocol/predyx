// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";

contract TestDepositToFillerPool is TestGammaMarket {
    function setUp() public override {
        TestGammaMarket.setUp();
    }

    // deposit succeeds
    // deposit fails if caller has no balance
}
