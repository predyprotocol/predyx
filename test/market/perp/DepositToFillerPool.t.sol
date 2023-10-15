// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";

contract TestPerpMarketDepositToFillerPool is TestPerpMarket {
    uint256 fillerPoolId;

    uint256 fromPrivateKey;
    address from;

    function setUp() public override {
        TestPerpMarket.setUp();

        fromPrivateKey = 0x12341234;
        from = vm.addr(fromPrivateKey);

        fillerPoolId = fillerMarket.addFillerPool(pairId);
    }

    function testCannotDepositToFillerPool() public {
        vm.expectRevert();
        fillerMarket.depositToFillerPool(fillerPoolId, 0);
    }

    function testCannotDepositToFillerPoolIfCallerIsNotFiller() public {
        vm.startPrank(from);

        vm.expectRevert(PerpMarket.CallerIsNotFiller.selector);
        fillerMarket.depositToFillerPool(fillerPoolId, 1000000);

        vm.stopPrank();
    }

    function testCannotDepositToFillerPoolIfBalanceIsZero() public {
        vm.startPrank(from);

        uint256 newFillerPoolId = fillerMarket.addFillerPool(pairId);

        vm.expectRevert(bytes("ERC20: insufficient allowance"));
        fillerMarket.depositToFillerPool(newFillerPoolId, 1000000);

        vm.stopPrank();
    }

    function testDepositToFillerPool(uint256 marginAmount) public {
        marginAmount = bound(marginAmount, 1, 1e18);

        fillerMarket.depositToFillerPool(fillerPoolId, marginAmount);

        (,,, int256 fillerMarginAmount,,,,,,) = fillerMarket.fillers(fillerPoolId);

        assertEq(fillerMarginAmount, int256(marginAmount));
    }
}
