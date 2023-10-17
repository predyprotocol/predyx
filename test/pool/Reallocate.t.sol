// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../mocks/TestTradeMarket.sol";
import "../../src/settlements/DirectSettlement.sol";

contract TestReallocate is TestPool {
    DirectSettlement settlement;
    TestTradeMarket tradeMarket;
    address filler;

    function setUp() public override {
        TestPool.setUp();

        registerPair(address(currency1), address(0));

        predyPool.supply(1, true, 1e8);
        predyPool.supply(1, false, 1e8);

        tradeMarket = new TestTradeMarket(predyPool);

        settlement = new DirectSettlement(predyPool, address(this));

        currency0.transfer(address(tradeMarket), 1e8);
        currency1.transfer(address(tradeMarket), 1e8);

        currency0.approve(address(settlement), 1e8);
        currency1.approve(address(settlement), 1e8);
    }

    // reallocate succeeds
    function testReallocateSucceeds() public {
        predyPool.reallocate(1, settlement.getSettlementParams(address(currency1), address(currency0), 1e4));

        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            1, 0, -9990, 10000, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
        );

        tradeMarket.trade(tradeParams, settlement.getSettlementParams(address(currency1), address(currency0), 1e4));

        _movePrice(true, 5 * 1e16);

        predyPool.reallocate(1, settlement.getSettlementParams(address(currency1), address(currency0), 14000));
    }

    // reallocate succeeds if totalAmount is 0
    // reallocate fails if current tick is within safe range
}
