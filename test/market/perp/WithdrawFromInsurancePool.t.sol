// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";

contract TestPerpMarketWithdrawFromFillerPool is TestPerpMarket {
    uint256 fromPrivateKey;
    address from;

    function setUp() public override {
        TestPerpMarket.setUp();

        fromPrivateKey = 0x12341234;
        from = vm.addr(fromPrivateKey);

        fillerMarket.addFillerPool(pairId);
    }

    function testWithdrawFromFillerPool() public {
        fillerMarket.depositToInsurancePool(pairId, 1000000);

        fillerMarket.withdrawFromInsurancePool(pairId, 1000000);
    }

    function testCannotWithdrawFromFillerPoolIfCallerIsNotFiller() public {
        fillerMarket.depositToInsurancePool(pairId, 1000000);

        vm.startPrank(from);

        vm.expectRevert(IFillerMarket.CallerIsNotFiller.selector);
        fillerMarket.withdrawFromInsurancePool(pairId, 1000000);

        vm.stopPrank();
    }
}
