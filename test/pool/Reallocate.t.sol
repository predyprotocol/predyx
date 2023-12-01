// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TestPool} from "./Setup.t.sol";
import {TestTradeMarket} from "../mocks/TestTradeMarket.sol";
import {DirectSettlement} from "../../src/settlements/DirectSettlement.sol";

contract TestReallocate is TestPool {
    DirectSettlement private settlement;
    TestTradeMarket private tradeMarket;
    address private filler;

    function setUp() public override {
        TestPool.setUp();

        registerPair(address(currency1), address(0));

        predyPool.supply(1, true, 1e8);
        predyPool.supply(1, false, 1e8);

        tradeMarket = new TestTradeMarket(predyPool);

        filler = vm.addr(12);
        settlement = new DirectSettlement(predyPool, filler);

        currency0.transfer(address(tradeMarket), 1e8);
        currency1.transfer(address(tradeMarket), 1e8);

        currency0.approve(address(settlement), 1e8);
        currency1.approve(address(settlement), 1e8);

        currency0.mint(filler, 1e10);
        currency1.mint(filler, 1e10);
        vm.startPrank(filler);
        currency0.approve(address(settlement), 1e10);
        currency1.approve(address(settlement), 1e10);
        vm.stopPrank();
    }

    function testReallocateFailsByInvalidPairId() public {
        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(address(currency1), address(currency0), 10000);

        vm.expectRevert(IPredyPool.InvalidPairId.selector);
        predyPool.reallocate(0, settlementData);

        vm.expectRevert(IPredyPool.InvalidPairId.selector);
        predyPool.reallocate(2, settlementData);
    }

    function testReallocateSucceeds() public {
        // reallocation never be happened if total amount is 0
        assertFalse(
            predyPool.reallocate(1, settlement.getSettlementParams(address(currency1), address(currency0), 1e4))
        );

        {
            IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
                1, 0, -99900, 100000, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
            );

            tradeMarket.trade(tradeParams, settlement.getSettlementParams(address(currency1), address(currency0), 1e4));
        }

        // reallocation never be happened if current tick is within safe range
        assertFalse(
            predyPool.reallocate(1, settlement.getSettlementParams(address(currency1), address(currency0), 1e4))
        );

        _movePrice(true, 5 * 1e16);

        uint256 snapshot = vm.snapshot();

        // reallocation is happened
        assertTrue(
            predyPool.reallocate(1, settlement.getSettlementParams(address(currency1), address(currency0), 15000))
        );

        vm.revertTo(snapshot);

        {
            // fails if quote token amount is not enough
            ISettlement.SettlementData memory settlementData =
                settlement.getSettlementParams(address(currency1), address(currency0), 10000);

            vm.expectRevert(IPredyPool.CurrencyNotSettled.selector);
            predyPool.reallocate(1, settlementData);
        }
    }
}
