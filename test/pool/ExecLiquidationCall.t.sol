// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../mocks/TestTradeMarket.sol";

contract TestExecLiquidationCall is TestPool {
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

    // liquidate succeeds if the vault is danger
    function testLiquidateSucceeds() public {
        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            1, 0, -1000, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
        );

        tradeMarket.trade(
            tradeParams, abi.encode(TestTradeMarket.SettlementParams(address(currency1), address(currency0)))
        );

        _movePrice(true);

        vm.warp(block.timestamp + 1 minutes);

        tradeMarket.execLiquidationCall(
            1, 1e18, abi.encode(TestTradeMarket.SettlementParams(address(currency1), address(currency0)))
        );
    }

    // liquidate fails if slippage too large
    function testLiquidateFailIfSlippageTooLarge() public {
        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            1, 0, -1000, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
        );

        bytes memory settlementData =
            abi.encode(TestTradeMarket.SettlementParams(address(currency1), address(currency0)));

        tradeMarket.trade(tradeParams, settlementData);

        _movePrice(true);

        vm.warp(block.timestamp + 30 minutes);

        tradeMarket.setMockPrice(20000);

        vm.expectRevert(IPredyPool.SlippageTooLarge.selector);
        tradeMarket.execLiquidationCall(1, 1e18, settlementData);
    }

    // liquidate succeeds by premium payment
    // liquidate succeeds with insolvent vault
    // liquidate fails if the vault is safe
    // liquidate fails after liquidation
}
