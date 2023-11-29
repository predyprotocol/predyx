// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";

contract TestWithdrawFromFillerPool is TestGammaMarket {
    function setUp() public override {
        TestGammaMarket.setUp();
    }

    // withdraw succeeds
    // withdraw succeeds with borrow fee
    // withdraw fails if there is no available pool balance
}
