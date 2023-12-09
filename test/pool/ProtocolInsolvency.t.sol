// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TestPool} from "./Setup.t.sol";
import {TestTradeMarket} from "../mocks/TestTradeMarket.sol";
import {DirectSettlement} from "../../src/settlements/DirectSettlement.sol";
import {IPredyPool} from "../../src/interfaces/IPredyPool.sol";
import {DataType} from "../../src/libraries/DataType.sol";

contract ProtocolInsolvencyTest is TestPool {
    DirectSettlement private settlement;
    TestTradeMarket private tradeMarket;
    address private filler;

    function setUp() public override {
        TestPool.setUp();

        registerPair(address(currency1), address(0));

        predyPool.supply(1, true, 1e8);
        predyPool.supply(1, false, 1e8);

        tradeMarket = new TestTradeMarket(predyPool);

        settlement = new DirectSettlement(predyPool, address(this));

        // currency0.transfer(address(tradeMarket), 1e10);
        currency1.transfer(address(tradeMarket), 1e10);

        currency0.approve(address(settlement), 1e10);
        currency1.approve(address(settlement), 1e10);
    }

    function _getTradeAfterParams(uint256 updateMarginAmount) internal view returns (TestTradeMarket.TradeAfterParams memory) {
        return TestTradeMarket.TradeAfterParams(address(this), address(currency1), updateMarginAmount);
    }

    function testNormalFlow() external {
        tradeMarket.trade(
            IPredyPool.TradeParams(1, 0, 1e6, 0, abi.encode(_getTradeAfterParams(1e7))),
            settlement.getSettlementParams(address(currency1), address(currency0), 1e4)
        );

        _movePrice(true, 1000);

        uint256 snapshot = vm.snapshot();

        vm.warp(block.timestamp + 1 days);

        tradeMarket.trade(
            IPredyPool.TradeParams(1, 1, -1e6, 0, abi.encode(_getTradeAfterParams(0))),
            settlement.getSettlementParams(address(currency1), address(currency0), 10100)
        );

        predyPool.withdraw(1, true, 1e18);
        predyPool.withdraw(1, false, 1e18);

        {
            DataType.Vault memory vault = predyPool.getVault(1);

            assertEq(vault.margin, 1e7 + 9958);
        }

        assertEq(currency0.balanceOf(address(predyPool)), 0);
        assertEq(currency1.balanceOf(address(predyPool)), 1e7 + 9959);

        vm.revertTo(snapshot);

        vm.warp(block.timestamp + 7 days);

        tradeMarket.trade(
            IPredyPool.TradeParams(1, 1, -1e6, 0, abi.encode(_getTradeAfterParams(0))),
            settlement.getSettlementParams(address(currency1), address(currency0), 10100)
        );

        predyPool.withdraw(1, true, 1e18);
        predyPool.withdraw(1, false, 1e18);

        {
            DataType.Vault memory vault = predyPool.getVault(1);

            assertEq(vault.margin, 1e7 + 9712);
        }

        assertEq(currency0.balanceOf(address(predyPool)), 0);
        assertEq(currency1.balanceOf(address(predyPool)), 1e7 + 9713);
    }

    function testEarnTradeFeeFlow() external {
        tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 0, -1e6, 1e6, abi.encode(_getTradeAfterParams(1e7))
            ),
            settlement.getSettlementParams(address(currency1), address(currency0), 1e4)
        );

        _movePrice(true, 1e15);
        for (uint256 i = 0; i < 10; i++) {
            _movePrice(false, 2 * 1e15);
            _movePrice(true, 2 * 1e15);
        }
        _movePrice(false, 1e15);

        vm.warp(block.timestamp + 1 days);

        tradeMarket.trade(
            IPredyPool.TradeParams(1, 1, 1e6, -1e6, abi.encode(_getTradeAfterParams(0))),
            settlement.getSettlementParams(address(currency1), address(currency0), 1e4)
        );

        predyPool.withdraw(1, true, 1e18);
        predyPool.withdraw(1, false, 1e18);

        {
            DataType.Vault memory vault = predyPool.getVault(1);

            assertEq(vault.margin, 10000013);
        }

        assertEq(currency0.balanceOf(address(predyPool)), 1);
        assertEq(currency1.balanceOf(address(predyPool)), 10000014);
    }

    function testBorrowSquartFlow() external {
        assertFalse(
            predyPool.reallocate(1, settlement.getSettlementParams(address(currency1), address(currency0), 1e4))
        );

        tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 0, -9 * 1e7, 1e8, abi.encode(_getTradeAfterParams(1e7))
            ),
            settlement.getSettlementParams(address(currency1), address(currency0), 1e4)
        );

        tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 0, 1e7, -1e7, abi.encode(_getTradeAfterParams(1e7))
            ),
            settlement.getSettlementParams(address(currency1), address(currency0), 1e4)
        );

        _movePrice(true, 3 * 1e16);

        // vm.warp(block.timestamp + 1 days);

        tradeMarket.trade(
            IPredyPool.TradeParams(1, 1, -1e7, 0, abi.encode(_getTradeAfterParams(0))),
            settlement.getSettlementParams(address(currency1), address(currency0), 10000)
        );


        tradeMarket.trade(
            IPredyPool.TradeParams(1, 2, -1e7, 1e7, abi.encode(_getTradeAfterParams(0))),
            settlement.getSettlementParams(address(currency1), address(currency0), 10000)
        );

        tradeMarket.trade(
            IPredyPool.TradeParams(1, 1, 1e8, -1e8, abi.encode(_getTradeAfterParams(0))),
            settlement.getSettlementParams(address(currency1), address(currency0), 10000)
        );

        predyPool.withdraw(1, true, 1e18);
        predyPool.withdraw(1, false, 1e18);

        // check payouts are correct
        {
            DataType.Vault memory vault1 = predyPool.getVault(1);
            assertEq(vault1.margin, 10050012);
        }

        {
            DataType.Vault memory vault2 = predyPool.getVault(2);
            assertEq(vault2.margin, 9999992);
        }

        assertEq(currency0.balanceOf(address(predyPool)), 4);
        assertEq(currency1.balanceOf(address(predyPool)), 20050029);
    }


    function testReallocationFlow() external {
        assertFalse(
            predyPool.reallocate(1, settlement.getSettlementParams(address(currency1), address(currency0), 1e4))
        );

        tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 0, -9 * 1e5, 1e6, abi.encode(_getTradeAfterParams(1e7))
            ),
            settlement.getSettlementParams(address(currency1), address(currency0), 1e4)
        );

        tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 0, 1e5, -1e5, abi.encode(_getTradeAfterParams(1e7))
            ),
            settlement.getSettlementParams(address(currency1), address(currency0), 1e4)
        );

        _movePrice(true, 5 * 1e16);

        // reallocation is happened
        assertTrue(
            predyPool.reallocate(1, settlement.getSettlementParams(address(currency1), address(currency0), 15000))
        );

        vm.warp(block.timestamp + 1 days);

        tradeMarket.trade(
            IPredyPool.TradeParams(1, 1, -1e5, 0, abi.encode(_getTradeAfterParams(0))),
            settlement.getSettlementParams(address(currency1), address(currency0), 15000)
        );

        _movePrice(false, 5 * 1e16);
        vm.warp(block.timestamp + 1 days);

        assertTrue(
            predyPool.reallocate(1, settlement.getSettlementParams(address(currency1), address(currency0), 9000))
        );

        tradeMarket.trade(
            IPredyPool.TradeParams(1, 2, -1e5, 1e5, abi.encode(_getTradeAfterParams(0))),
            settlement.getSettlementParams(address(currency1), address(currency0), 10000)
        );

        tradeMarket.trade(
            IPredyPool.TradeParams(1, 1, 1e6, -1e6, abi.encode(_getTradeAfterParams(0))),
            settlement.getSettlementParams(address(currency1), address(currency0), 10000)
        );

        predyPool.withdraw(1, true, 1e18);
        predyPool.withdraw(1, false, 1e18);

        // check payouts are correct
        {
            DataType.Vault memory vault1 = predyPool.getVault(1);
            assertEq(vault1.margin, 10050012);
        }

        {
            DataType.Vault memory vault2 = predyPool.getVault(2);
            assertEq(vault2.margin, 9999992);
        }

        assertEq(currency0.balanceOf(address(predyPool)), 4);
        assertEq(currency1.balanceOf(address(predyPool)), 20050029);
    }

    function testReallocationEdgeFlow() external {
        assertFalse(
            predyPool.reallocate(1, settlement.getSettlementParams(address(currency1), address(currency0), 1e4))
        );

        tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 0, -9 * 1e5, 1e6, abi.encode(_getTradeAfterParams(1e7))
            ),
            settlement.getSettlementParams(address(currency1), address(currency0), 1e4)
        );

        tradeMarket.trade(
            IPredyPool.TradeParams(
                1, 0, -9 * 1e5, 1e6, abi.encode(_getTradeAfterParams(1e7))
            ),
            settlement.getSettlementParams(address(currency1), address(currency0), 1e4)
        );

        _movePrice(true, 5 * 1e16);

        // reallocation is happened
        assertTrue(
            predyPool.reallocate(1, settlement.getSettlementParams(address(currency1), address(currency0), 15000))
        );

        vm.warp(block.timestamp + 1 days);

        tradeMarket.trade(
            IPredyPool.TradeParams(1, 2, -1e5, 0, abi.encode(_getTradeAfterParams(0))),
            settlement.getSettlementParams(address(currency1), address(currency0), 15000)
        );

        tradeMarket.trade(
            IPredyPool.TradeParams(1, 1, -1e5, 0, abi.encode(_getTradeAfterParams(0))),
            settlement.getSettlementParams(address(currency1), address(currency0), 15000)
        );

        _movePrice(false, 5 * 1e16);
        vm.warp(block.timestamp + 1 days);

        assertTrue(
            predyPool.reallocate(1, settlement.getSettlementParams(address(currency1), address(currency0), 10000))
        );

        tradeMarket.trade(
            IPredyPool.TradeParams(1, 1, 1e6, -1e6, abi.encode(_getTradeAfterParams(0))),
            settlement.getSettlementParams(address(currency1), address(currency0), 10000)
        );

        tradeMarket.trade(
            IPredyPool.TradeParams(1, 2, 1e6, -1e6, abi.encode(_getTradeAfterParams(0))),
            settlement.getSettlementParams(address(currency1), address(currency0), 10000)
        );

        predyPool.withdraw(1, true, 1e18);
        predyPool.withdraw(1, false, 1e18);

        // check payouts are correct
        {
            DataType.Vault memory vault1 = predyPool.getVault(1);
            assertEq(vault1.margin, 10050012);
        }

        {
            DataType.Vault memory vault2 = predyPool.getVault(2);
            assertEq(vault2.margin, 10050012);
        }

        assertEq(currency0.balanceOf(address(predyPool)), 3);
        assertEq(currency1.balanceOf(address(predyPool)), 20100076);
    }
}
