// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../mocks/TestTradeMarket.sol";
import "../../src/settlements/DirectSettlement.sol";

contract TestExecLiquidationCall is TestPool {
    TestTradeMarket _tradeMarket;
    DirectSettlement _settlement;

    function setUp() public override {
        TestPool.setUp();

        registerPair(address(currency1));

        predyPool.supply(1, true, 1e10);
        predyPool.supply(1, false, 1e10);

        _tradeMarket = new TestTradeMarket(predyPool);
        _settlement = new DirectSettlement(predyPool);

        currency0.transfer(address(_tradeMarket), 1e10);
        currency1.transfer(address(_tradeMarket), 1e10);

        currency0.transfer(address(_settlement), 1e10);
        currency1.transfer(address(_settlement), 1e10);
    }

    function checkMarginGeZero(uint256 vaultId) internal {
        DataType.Vault memory vault = predyPool.getVault(vaultId);
        assertGe(vault.margin, 0);
    }

    function checkMarginLeZero(uint256 vaultId) internal {
        DataType.Vault memory vault = predyPool.getVault(vaultId);
        assertLe(vault.margin, 0);
    }

    function _getSettlementData(uint256 price) internal view returns (ISettlement.SettlementData memory) {
        return _settlement.getSettlementParams(address(currency1), address(currency0), price);
    }

    // liquidate succeeds if the vault is danger
    function testLiquidateSucceedsIfVaultIsDanger() public {
        IPredyPool.TradeParams memory tradeParams =
            IPredyPool.TradeParams(1, 0, -4 * 1e8, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e8)));

        _tradeMarket.trade(tradeParams, _getSettlementData(1e4));

        _movePrice(true, 6 * 1e16);
        //1000000 1106398

        vm.warp(block.timestamp + 20 minutes);

        _tradeMarket.execLiquidationCall(1, 1e18, _getSettlementData(11000));

        checkMarginGeZero(1);
    }

    // liquidate fails if slippage too large
    function testLiquidateFailIfSlippageTooLarge() public {
        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            1, 0, -4 * 1e8, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e8))
        );

        _tradeMarket.trade(tradeParams, _getSettlementData(1e4));

        _movePrice(true, 6 * 1e16);

        vm.warp(block.timestamp + 30 minutes);

        {
            ISettlement.SettlementData memory settlementData =
               _getSettlementData(20000);

            vm.expectRevert(IPredyPool.SlippageTooLarge.selector);
            _tradeMarket.execLiquidationCall(1, 1e18, settlementData);
        }
    }

    // liquidate succeeds by premium payment
    function testLiquidateSucceedsByPremiumPayment() public {
        predyPool.trade(IPredyPool.TradeParams(1, 0, - 2 * 1e8, 2 * 1e8, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e7))), _getSettlementData(1e4));

        predyPool.trade(IPredyPool.TradeParams(2, 0, 1e8, -1e8, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e7))), _getSettlementData(1e4));

        _movePrice(true, 2 * 1e16);
        _movePrice(false, 2 * 1e16);

        vm.warp(block.timestamp + 1 minutes);

        predyPool.execLiquidationCall(2, 1e18, _getSettlementData(10000));

        checkMarginGeZero(2);
    }    

    // liquidate succeeds with insolvent vault
    function testLiquidateSucceedsWithInsolvent() public {
        IPredyPool.TradeParams memory tradeParams =
            IPredyPool.TradeParams(1, 0, -48 * 1e7, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e8)));

        _tradeMarket.trade(tradeParams, _getSettlementData(1e4));

        _movePrice(true, 8 * 1e16);

        vm.warp(block.timestamp + 30 minutes);

        predyPool.execLiquidationCall(1, 1e18, _getSettlementData(12100));

        checkMarginLeZero(1);
    }

    // liquidate fails if the vault is safe
    function testLiquidateFailsIfVaultIsSafe() public {
        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            1, 0, -4 * 1e8, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e8))
        );

        ISettlement.SettlementData memory settlementData =
            _settlement.getSettlementParams(address(currency1), address(currency0), 1e4);

        _tradeMarket.trade(tradeParams, settlementData);

        vm.expectRevert(IPredyPool.VaultIsNotDanger.selector);
        _tradeMarket.execLiquidationCall(1, 1e18, settlementData);
    }

    // liquidate fails after liquidation
    function testLiquidateFailsAfterLiquidation() public {
        IPredyPool.TradeParams memory tradeParams =
            IPredyPool.TradeParams(1, 0, -4 * 1e8, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e8)));

        _tradeMarket.trade(tradeParams, _getSettlementData(1e4));

        _movePrice(true, 6 * 1e16);

        vm.warp(block.timestamp + 20 minutes);

        ISettlement.SettlementData memory settlementData = _getSettlementData(11000);

        _tradeMarket.execLiquidationCall(1, 1e18, settlementData);

        vm.expectRevert(IPredyPool.VaultIsNotDanger.selector);
        _tradeMarket.execLiquidationCall(1, 1e18, settlementData);
    }
}
