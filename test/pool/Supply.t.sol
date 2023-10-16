// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Setup.t.sol";

contract TestSupply is TestPool {
    address supplyTokenAddress;

    event TokenSupplied(address account, uint256 pairId, bool isStable, uint256 suppliedAmount);

    function setUp() public override {
        TestPool.setUp();

        registerPair(address(currency1), address(0));

        Perp.PairStatus memory pair = predyPool.getPairStatus(1);

        supplyTokenAddress = pair.basePool.supplyTokenAddress;

        currency0.approve(address(predyPool), type(uint256).max);
        currency1.approve(address(predyPool), type(uint256).max);
    }

    // supply succeeds
    function testSupplySucceeds(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        uint256 beforeBalance = IERC20(currency0).balanceOf(address(this));

        currency0.approve(address(predyPool), 1e6);

        if (amount <= 1e6) {
            vm.expectEmit(true, true, true, true);
            emit TokenSupplied(address(this), 1, false, amount);
        } else {
            vm.expectRevert(bytes("STF"));
        }
        predyPool.supply(1, false, amount);

        if (amount <= 1e6) {
            uint256 afterBalance = IERC20(currency0).balanceOf(address(this));

            assertEq(beforeBalance - afterBalance, amount);

            assertEq(IERC20(supplyTokenAddress).balanceOf(address(this)), amount);
        }
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
