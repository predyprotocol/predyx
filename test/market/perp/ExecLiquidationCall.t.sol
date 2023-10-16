// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import {BaseHookCallback} from "../../../src/base/BaseHookCallback.sol";

contract TestPerpExecLiquidationCall is TestPerpMarket {
    function setUp() public override {
        TestPerpMarket.setUp();
    }

    // liquidate succeeds if the vault is danger
    function testLiquidateSucceedsIfVaultIsDanger(uint256 closeRatio) public {}

    // liquidate succeeds and only filler can cover negative margin
    function testLiquidateSucceedsIfFillerCoverNegativeMargin() public {}

    // liquidate fails if slippage too large
    function testLiquidateFailIfSlippageTooLarge() public {
        //
    }

    // liquidate succeeds by premium payment
    function testLiquidateSucceedsByPremiumPayment() public {}

    // liquidate succeeds with insolvent vault
    function testLiquidateSucceedsWithInsolvent() public {}

    // liquidate fails if the vault is safe
    function testLiquidateFailsIfVaultIsSafe() public {}

    // liquidate fails after liquidation
    function testLiquidateFailsAfterLiquidation() public {}
}
