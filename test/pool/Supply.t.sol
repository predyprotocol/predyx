// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Setup.t.sol";

contract TestSupply is TestPool {
    address supplyTokenAddress;

    event TokenSupplied(address account, uint256 pairId, bool isStable, uint256 suppliedAmount);

    function setUp() public override {
        TestPool.setUp();

        registerPair(address(currency1));

        Perp.PairStatus memory pair = predyPool.getPairStatus(1);

        supplyTokenAddress = pair.basePool.supplyTokenAddress;

        currency0.approve(address(predyPool), type(uint256).max);
        currency1.approve(address(predyPool), type(uint256).max);
    }

    // supply succeeds
    function testSupplySucceeds() public {
        vm.expectEmit(true, true, true, true);
        emit TokenSupplied(address(this), 1, false, 100);
        predyPool.supply(1, false, 100);

        assertEq(IERC20(supplyTokenAddress).balanceOf(address(this)), 100);
    }

    // Amount must be greater than 0
    function testCannotSupply_IfAmountIsZero() public {
        vm.expectRevert(IPredyPool.InvalidAmount.selector);
        predyPool.supply(1, false, 0);
    }

    // supply fails if pairId is 0
    function testCannotSupply_IfPairIdIsZero() public {
        vm.expectRevert(IPredyPool.InvalidPairId.selector);
        predyPool.supply(0, false, 100);
    }
}
