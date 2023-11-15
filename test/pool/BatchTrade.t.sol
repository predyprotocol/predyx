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

    uint256 whitelistPairId;

    function setUp() public override {
        TestPool.setUp();

        registerPair(address(currency1), address(0), false);
        whitelistPairId = registerPair(address(currency1), address(0), true);

        predyPool.supply(1, true, 1e8);
        predyPool.supply(1, false, 1e8);
        predyPool.supply(whitelistPairId, true, 1e8);
        predyPool.supply(whitelistPairId, false, 1e8);

        tradeMarket = new TestTradeMarket(predyPool);
        tradeMarket2 = new TestTradeMarket(predyPool);
        testSettlementCurrencyNotSettled = new TestSettlementCurrencyNotSettled(predyPool);
        testSettlementReentrant = new TestSettlementReentrant(predyPool);
        directSettlement = new DirectSettlement(predyPool, address(this));

        currency1.transfer(address(tradeMarket), 1e10);

        currency0.approve(address(directSettlement), 1e10);
        currency1.approve(address(directSettlement), 1e10);

        currency0.transfer(address(testSettlementCurrencyNotSettled), 1e8);
        currency1.transfer(address(testSettlementCurrencyNotSettled), 1e8);

        currency0.transfer(address(testSettlementReentrant), 1e8);
        currency1.transfer(address(testSettlementReentrant), 1e8);

        filler = address(this);
    }

    function testBatchTradeSucceeds() public {
        IPredyPool.TradeParams[] memory tradeParamsList = new IPredyPool.TradeParams[](2);
        ISettlement.SettlementData[] memory settlementDataList = new ISettlement.SettlementData[](2);

        tradeParamsList[0] = IPredyPool.TradeParams(
            1, 0, -900, 1000, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
        );
        tradeParamsList[1] = IPredyPool.TradeParams(
            1, 0, -900, 1000, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
        );

        settlementDataList[0] = directSettlement.getSettlementParams(address(currency1), address(currency0), 1e4);
        settlementDataList[1] = directSettlement.getSettlementParams(address(currency1), address(currency0), 1e4);

        IPredyPool.TradeResult[] memory tradeResults = tradeMarket.batchTrade(tradeParamsList, settlementDataList);

        assertEq(tradeResults[0].payoff.perpEntryUpdate, 900);
        assertEq(tradeResults[0].payoff.sqrtEntryUpdate, -2000);
        assertEq(tradeResults[0].payoff.perpPayoff, 0);
        assertEq(tradeResults[0].payoff.sqrtPayoff, 0);

        DataType.Vault memory vault = predyPool.getVault(2);

        assertEq(vault.margin, 1e6);
    }
}
