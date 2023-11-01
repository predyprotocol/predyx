// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";

contract TestPerpMarketDepositToFillerPool is TestPerpMarket {
    uint256 fromPrivateKey;
    address from;

    function setUp() public override {
        TestPerpMarket.setUp();

        fromPrivateKey = 0x12340012;
        from = vm.addr(fromPrivateKey);

        fillerMarket.addFillerPool(pairId);
    }

    function testCannotDepositToFillerPool() public {
        vm.expectRevert();
        fillerMarket.depositToInsurancePool(pairId, 0);
    }

    function testCannotDepositToFillerPoolIfCallerIsNotFiller() public {
        vm.startPrank(from);

        vm.expectRevert(IFillerMarket.CallerIsNotFiller.selector);
        fillerMarket.depositToInsurancePool(pairId, 1000000);

        vm.stopPrank();
    }

    function testCannotDepositToFillerPoolIfBalanceIsZero() public {
        vm.startPrank(from);

        fillerMarket.addFillerPool(pairId);

        vm.expectRevert(bytes("ERC20: insufficient allowance"));
        fillerMarket.depositToInsurancePool(pairId, 1000000);

        vm.stopPrank();
    }

    function testDepositToFillerPool(uint256 marginAmount) public {
        marginAmount = bound(marginAmount, 1, 1e18);

        fillerMarket.depositToInsurancePool(pairId, marginAmount);

        (,,, int256 fillerMarginAmount,,,,,,) = fillerMarket.insurancePools(address(this), pairId);

        assertEq(fillerMarginAmount, int256(marginAmount));
    }
}
