// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../mocks/TestTradeMarket.sol";
import "../../src/settlements/DirectSettlement.sol";

contract TestExecLiquidationCall is TestPool {
    TestTradeMarket _tradeMarket;
    DirectSettlement _settlement;
    address filler;

    function setUp() public override {
        TestPool.setUp();

        registerPair(address(currency1), address(0));

        predyPool.supply(1, true, 1e10);
        predyPool.supply(1, false, 1e10);

        _tradeMarket = new TestTradeMarket(predyPool);
        _settlement = new DirectSettlement(predyPool);

        currency0.transfer(address(_tradeMarket), 1e10);
        currency1.transfer(address(_tradeMarket), 1e10);

        currency0.approve(address(_settlement), 1e10);
        currency1.approve(address(_settlement), 1e10);

        filler = address(this);
    }

    function checkMarginEqZero(uint256 vaultId) internal {
        DataType.Vault memory vault = predyPool.getVault(vaultId);
        assertEq(vault.margin, 0);
    }

    function checkMarginGtZero(uint256 vaultId) internal {
        DataType.Vault memory vault = predyPool.getVault(vaultId);
        assertGt(vault.margin, 0);
    }

    function _getSettlementData(uint256 price) internal view returns (ISettlement.SettlementData memory) {
        return _settlement.getSettlementParams(filler, address(currency1), address(currency0), price);
    }

    // liquidate succeeds if the vault is danger
    function testLiquidateSucceedsIfVaultIsDanger(uint256 closeRatio) public {
        closeRatio = bound(closeRatio, 1e17, 1e18);

        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            1, 0, -4 * 1e8, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e8))
        );

        _tradeMarket.trade(tradeParams, _getSettlementData(1e4));

        _movePrice(true, 6 * 1e16);

        vm.warp(block.timestamp + 30 minutes);

        uint256 beforeMargin = currency1.balanceOf(address(_tradeMarket));
        _tradeMarket.execLiquidationCall(1, closeRatio, _getSettlementData(11000));
        uint256 afterMargin = currency1.balanceOf(address(_tradeMarket));

        if (closeRatio == 1e18) {
            assertGt(afterMargin - beforeMargin, 0);
        } else {
            checkMarginGtZero(1);
        }
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
            ISettlement.SettlementData memory settlementData = _getSettlementData(20000);

            vm.expectRevert(LiquidationLogic.SlippageTooLarge.selector);
            _tradeMarket.execLiquidationCall(1, 1e18, settlementData);
        }
    }

    // liquidate succeeds by premium payment
    function testLiquidateSucceedsByPremiumPayment() public {
        _tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 0, -2 * 1e8, 2 * 1e8, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e7))
            ),
            _getSettlementData(1e4)
        );

        _tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 0, 1e8, -1e8, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e6))
            ),
            _getSettlementData(1e4)
        );

        _movePrice(true, 2 * 1e16);
        _movePrice(false, 2 * 1e16);

        vm.warp(block.timestamp + 10 minutes);

        predyPool.execLiquidationCall(2, 1e18, _getSettlementData(10000));

        checkMarginEqZero(2);
    }

    // liquidate succeeds with insolvent vault
    function testLiquidateSucceedsWithInsolvent() public {
        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            1, 0, -48 * 1e7, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e8))
        );

        _tradeMarket.trade(tradeParams, _getSettlementData(1e4));

        _movePrice(true, 8 * 1e16);

        vm.warp(block.timestamp + 30 minutes);

        uint256 beforeMargin = currency1.balanceOf(address(this));
        predyPool.execLiquidationCall(1, 1e18, _getSettlementData(12100));
        uint256 afterMargin = currency1.balanceOf(address(this));

        assertGt(beforeMargin - afterMargin, 0);
        checkMarginEqZero(1);
    }

    // liquidate fails if the vault is safe
    function testLiquidateFailsIfVaultIsSafe() public {
        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            1, 0, -4 * 1e8, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e8))
        );

        ISettlement.SettlementData memory settlementData =
            _settlement.getSettlementParams(filler, address(currency1), address(currency0), 1e4);

        _tradeMarket.trade(tradeParams, settlementData);

        vm.expectRevert(IPredyPool.VaultIsNotDanger.selector);
        _tradeMarket.execLiquidationCall(1, 1e18, settlementData);
    }

    // liquidate fails after liquidation
    function testLiquidateFailsAfterLiquidation() public {
        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            1, 0, -4 * 1e8, 0, abi.encode(TestTradeMarket.TradeAfterParams(address(currency1), 1e8))
        );

        _tradeMarket.trade(tradeParams, _getSettlementData(1e4));

        _movePrice(true, 6 * 1e16);

        vm.warp(block.timestamp + 30 minutes);

        ISettlement.SettlementData memory settlementData = _getSettlementData(11000);

        _tradeMarket.execLiquidationCall(1, 1e18, settlementData);

        vm.expectRevert(IPredyPool.VaultIsNotDanger.selector);
        _tradeMarket.execLiquidationCall(1, 1e18, settlementData);
    }
}
