// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import {BaseHookCallback} from "../../../src/base/BaseHookCallback.sol";

contract TestPerpMarketCallback is TestPerpMarket {
    function setUp() public override {
        TestPerpMarket.setUp();
    }

    function testCannotCallTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) public {
        vm.expectRevert(BaseHookCallback.CallerIsNotPredyPool.selector);
        fillerMarket.predyTradeAfterCallback(tradeParams, tradeResult);
    }
}
