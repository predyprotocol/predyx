// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestExecLiquidationCall is TestPool {
    function setUp() public override {
        TestPool.setUp();
    }

    // liquidate succeeds if the vault is danger
    // liquidate succeeds by premium payment
    // liquidate succeeds with insolvent vault
    // liquidate fails if the vault is safe
    // liquidate fails after liquidation
}
