// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";
import "../mocks/TestTradeMarket.sol";

contract TestTrade is TestPool {
    TestTradeMarket tradeMarket;

    function setUp() public override {
        TestPool.setUp();

        registerPair(address(currency1));

        currency0.approve(address(predyPool), type(uint256).max);
        currency1.approve(address(predyPool), type(uint256).max);

        predyPool.supply(1, true, 1e6);
        predyPool.supply(1, false, 1e6);

        tradeMarket = new TestTradeMarket(predyPool);

        currency0.transfer(address(tradeMarket), 1e6);
        currency1.transfer(address(tradeMarket), 1e6);
    }

    function testTradeSucceeds() public {
        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(1, 1, -900, 1000, "");

        IPredyPool.TradeResult memory tradeResult = tradeMarket.trade(
            1, tradeParams, abi.encode(TestTradeMarket.SettlementParams(address(currency1), address(currency0)))
        );

        assertEq(tradeResult.payoff.perpEntryUpdate, 100);
    }

    // trade succeeds for open
    // trade succeeds for close
    // trade succeeds for update
    // trade succeeds after reallocated

    // trade succeeds with callback
    // trade fails if currency not settled

    // trade fails if caller is not vault owner
    // trade fails if pairId does not exist
    // trade fails if the vault is not safe
    // trade fails if asset can not cover borrow
    // trade fails if sqrt liquidity can not cover sqrt borrow
    // trade fails if current tick is not within safe range
}
