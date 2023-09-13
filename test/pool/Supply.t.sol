// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestSupply is TestPool {

    function setUp() public override {
        TestPool.setUp();
    }

    // supply
    function testSupplySucceeds() public {
        predyPool.supply(1, false, 100, 100);

        //IPredyPool memory predyPool = predyPool.getPairStatus(pairId);
        //assertEq(predyPool.);
    }

    function testCannotSupplyIfAmountExceedsMax() public {
        vm.expectRevert(IPredyPool.SupplyAmountExceedsMax.selector);
        predyPool.supply(1, false, 100, 90);
    }

    // Amount must be greater than 0
    function testCannotSupplyIfAmountIsZero() public {
        vm.expectRevert(IPredyPool.InvalidAmount.selector);
        predyPool.supply(1, false, 0, 0);
    }

    // supply fails if SupplyAmountExceedsMax
    // supply fails if amount is 0
    // supply fails if pairId is 0
}
