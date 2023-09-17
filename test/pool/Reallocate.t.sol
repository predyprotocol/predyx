// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../mocks/TestTradeMarket.sol";

contract TestReallocate is TestPool {
    TestTradeMarket tradeMarket;

    function setUp() public override {
        TestPool.setUp();

        registerPair(address(currency1));

        predyPool.supply(1, true, 1e8);
        predyPool.supply(1, false, 1e8);

        tradeMarket = new TestTradeMarket(predyPool);

        currency0.transfer(address(tradeMarket), 1e8);
        currency1.transfer(address(tradeMarket), 1e8);
    }

    // reallocate succeeds
    function testReallocateSucceeds() public {
        predyPool.reallocate(1);

        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            1, 0, -9990, 10000, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
        );
        
        tradeMarket.trade(
            tradeParams, abi.encode(TestTradeMarket.SettlementParams(address(currency1), address(currency0)))
        );

        _movePrice(true, 5 * 1e16);

        predyPool.reallocate(1);
    }


    // reallocate succeeds if totalAmount is 0
    // reallocate fails if current tick is within safe range
}
