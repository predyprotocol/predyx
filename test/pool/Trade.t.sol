// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../../src/settlements/DirectSettlement.sol";
import "../mocks/TestTradeMarket.sol";
import "../mocks/TestSettlement.sol";

contract TestTrade is TestPool {
    TestTradeMarket tradeMarket;
    TestTradeMarket tradeMarket2;
    TestSettlementCurrencyNotSettled testSettlementCurrencyNotSettled;
    TestSettlementReentrant testSettlementReentrant;
    DirectSettlement directSettlement;
    address filler;

    function setUp() public override {
        TestPool.setUp();

        registerPair(address(currency1));

        predyPool.supply(1, true, 1e8);
        predyPool.supply(1, false, 1e8);

        tradeMarket = new TestTradeMarket(predyPool);
        tradeMarket2 = new TestTradeMarket(predyPool);
        testSettlementCurrencyNotSettled = new TestSettlementCurrencyNotSettled(predyPool);
        testSettlementReentrant = new TestSettlementReentrant(predyPool);
        directSettlement = new DirectSettlement(predyPool);

        currency0.transfer(address(tradeMarket), 1e8);
        currency1.transfer(address(tradeMarket), 1e8);

        currency0.approve(address(directSettlement), 1e8);
        currency1.approve(address(directSettlement), 1e8);

        currency0.transfer(address(testSettlementCurrencyNotSettled), 1e8);
        currency1.transfer(address(testSettlementCurrencyNotSettled), 1e8);

        currency0.transfer(address(testSettlementReentrant), 1e8);
        currency1.transfer(address(testSettlementReentrant), 1e8);

        filler = address(this);
    }

    function testTradeSucceeds() public {
        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            1, 0, -900, 1000, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
        );

        IPredyPool.TradeResult memory tradeResult = tradeMarket.trade(
            tradeParams, directSettlement.getSettlementParams(filler, address(currency1), address(currency0), 1e4)
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
                1, 0, -99 * 1e4, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e8))
            ),
            directSettlement.getSettlementParams(filler, address(currency1), address(currency0), 1e4)
        );

        IPredyPool.TradeResult memory tradeResult = tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 1, 99 * 1e4, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 0))
            ),
            directSettlement.getSettlementParams(filler, address(currency1), address(currency0), 1e4)
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
            abi.encode(TestSettlementCurrencyNotSettled.SettlementParams(address(currency1), 100, 70));

        vm.expectRevert(IPredyPool.CurrencyNotSettled.selector);
        tradeMarket.trade(
            tradeParams, ISettlement.SettlementData(address(testSettlementCurrencyNotSettled), settlementData)
        );
    }

    // trade fails if caller is not vault owner
    function testTradeFails_IfCallerIsNotVaultOwner() public {
        IPredyPool.TradeResult memory tradeResult = tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 0, -99 * 1e4, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e8))
            ),
            directSettlement.getSettlementParams(filler, address(currency1), address(currency0), 1e4)
        );

        bytes memory extraData = abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 0));
        ISettlement.SettlementData memory settlementData =
            directSettlement.getSettlementParams(filler, address(currency1), address(currency0), 1e4);

        vm.expectRevert(IPredyPool.CallerIsNotVaultOwner.selector);
        tradeMarket2.trade(IPredyPool.TradeParams(1, tradeResult.vaultId, 99 * 1e4, 0, extraData), settlementData);
    }

    // trade fails if pairId does not exist
    // trade fails if the vault is not safe
    // trade fails if asset can not cover borrow
    // trade fails if sqrt liquidity can not cover sqrt borrow
    // trade fails if current tick is not within safe range
    function testTradeFailsIfCurrentTickIsNotInRange() public {
        {
            IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
                1, 0, -900, 1000, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
            );

            tradeMarket.trade(
                tradeParams, directSettlement.getSettlementParams(filler, address(currency1), address(currency0), 1e4)
            );
        }

        _movePrice(true, 5 * 1e16);

        {
            IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
                1, 0, 400, -500, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
            );

            ISettlement.SettlementData memory settlementData =
                directSettlement.getSettlementParams(filler, address(currency1), address(currency0), 1e4);

            vm.expectRevert(bytes("P2"));
            tradeMarket.trade(tradeParams, settlementData);
        }
    }

    // trade fails in callback
    function testCannotTradeReentrant() public {
        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(1, 0, -900, 1000, "");
        bytes memory settlementData = abi.encode(
            TestSettlementReentrant.SettlementParams(
                address(currency1),
                100,
                70,
                tradeParams,
                directSettlement.getSettlementParams(filler, address(currency1), address(currency0), 1e4)
            )
        );

        vm.expectRevert(abi.encodeWithSelector(IPredyPool.LockedBy.selector, address(testSettlementReentrant)));
        tradeMarket.trade(tradeParams, ISettlement.SettlementData(address(testSettlementReentrant), settlementData));
    }
}
