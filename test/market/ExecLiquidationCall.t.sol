// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestExecLiquidationCall is TestMarket {

    function setUp() public override {
        TestMarket.setUp();
    }
    
    // liquidate fails if the vault does not exist
    // liquidate fails if the vault is safe

    // liquidate succeeds if the vault is danger
    // liquidate succeeds with insolvent vault (compensated from filler pool)
}
