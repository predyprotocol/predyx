// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../mocks/TestTradeMarket.sol";

contract TestTrade is TestPool {
    TestTradeMarket tradeMarket;
    TestTradeMarket2 tradeMarket2;

    function setUp() public override {
        TestPool.setUp();

        registerPair(address(currency1));

        predyPool.supply(1, true, 1e8);
        predyPool.supply(1, false, 1e8);

        tradeMarket = new TestTradeMarket(predyPool);
        tradeMarket2 = new TestTradeMarket2(predyPool);

        currency0.transfer(address(tradeMarket), 1e8);
        currency1.transfer(address(tradeMarket), 1e8);

        currency0.transfer(address(tradeMarket2), 1e8);
        currency1.transfer(address(tradeMarket2), 1e8);
    }

    function testTradeSucceeds() public {
        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            1, 0, -900, 1000, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
        );

        IPredyPool.TradeResult memory tradeResult = tradeMarket.trade(
            tradeParams, abi.encode(TestTradeMarket.SettlementParams(address(currency1), address(currency0)))
        );

        assertEq(tradeResult.payoff.perpEntryUpdate, 900);
        assertEq(tradeResult.payoff.sqrtEntryUpdate, -2000);
        assertEq(tradeResult.payoff.perpPayoff, 0);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);

        DataType.Vault memory vault = predyPool.getVault(1);

        assertEq(vault.margin, 1e6);
    }

    // trade succeeds for open
    // trade succeeds for close
    function testTradeSucceedsForClose() public {
        tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 0, -99 * 1e4, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
            ),
            abi.encode(TestTradeMarket.SettlementParams(address(currency1), address(currency0)))
        );

        IPredyPool.TradeResult memory tradeResult = tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 1, 99 * 1e4, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 0))
            ),
            abi.encode(TestTradeMarket.SettlementParams(address(currency1), address(currency0)))
        );

        assertEq(tradeResult.payoff.perpPayoff, 0);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
    }

    // trade succeeds for update
    // trade succeeds after reallocated

    // trade succeeds with callback
    // trade fails if currency not settled
    function testCannotTrade_IfCurrencyNotSettled() public {
        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(1, 0, -900, 1000, "");
        bytes memory settlementData =
            abi.encode(TestTradeMarket2.SettlementParams(70, 100, address(currency0), address(currency1), true));

        vm.expectRevert(IPredyPool.CurrencyNotSettled.selector);
        tradeMarket2.trade(tradeParams, settlementData);
    }

    // trade fails if caller is not vault owner
    function testTradeFails_IfCallerIsNotVaultOwner() public {
        IPredyPool.TradeResult memory tradeResult = tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 0, -99 * 1e4, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
            ),
            abi.encode(TestTradeMarket.SettlementParams(address(currency1), address(currency0)))
        );

        bytes memory extraData = abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 0));
        bytes memory settlementData =
            abi.encode(TestTradeMarket.SettlementParams(address(currency1), address(currency0)));

        vm.expectRevert(IPredyPool.CallerIsNotVaultOwner.selector);
        tradeMarket2.trade(IPredyPool.TradeParams(1, tradeResult.vaultId, 99 * 1e4, 0, extraData), settlementData);
    }

    // trade fails if pairId does not exist
    // trade fails if the vault is not safe
    // trade fails if asset can not cover borrow
    // trade fails if sqrt liquidity can not cover sqrt borrow
    // trade fails if current tick is not within safe range
}
