// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import "forge-std/console2.sol";

contract TestPerpExecuteOrder is TestPerpMarket {
    bytes normalSwapRoute;
    uint256 fromPrivateKey1;
    address from1;
    uint256 fromPrivateKey2;
    address from2;

    function setUp() public override {
        TestPerpMarket.setUp();

        registerPair(address(currency1), address(0));
        fillerMarket.updateQuoteTokenMap(1);

        predyPool.supply(1, true, 1e10);
        predyPool.supply(1, false, 1e10);

        normalSwapRoute = abi.encodePacked(address(currency0), uint24(500), address(currency1));

        // fillerMarket.depositToFillerPool(100 * 1e6);

        fromPrivateKey1 = 0x12341234;
        from1 = vm.addr(fromPrivateKey1);
        fromPrivateKey2 = 0x1235678;
        from2 = vm.addr(fromPrivateKey2);

        currency1.mint(from1, type(uint128).max);
        currency1.mint(from2, type(uint128).max);

        vm.prank(from1);
        currency1.approve(address(permit2), type(uint256).max);

        vm.prank(from2);
        currency1.approve(address(permit2), type(uint256).max);
    }

    // executeOrder succeeds for open(pnl, interest, premium, borrow fee)
    function testExecuteOrderSucceedsForOpen() public {
        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
                1,
                address(currency1),
                -1000,
                2 * 1e6,
                address(0),
                0,
                0,
                0,
                address(limitOrderValidator),
                abi.encode(PerpLimitOrderValidationData(0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            ISettlement.SettlementData memory settlementData =
                settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0);

            vm.startPrank(from1);
            vm.expectRevert(IFillerMarket.CallerIsNotFiller.selector);
            fillerMarket.executeOrder(signedOrder, settlementData);
            vm.stopPrank();

            IPredyPool.TradeResult memory tradeResult = fillerMarket.executeOrder(signedOrder, settlementData);

            assertEq(tradeResult.payoff.perpEntryUpdate, 998);
            assertEq(tradeResult.payoff.sqrtEntryUpdate, 0);
            assertEq(tradeResult.payoff.perpPayoff, 0);
            assertEq(tradeResult.payoff.sqrtPayoff, 0);
        }

        // Close position by trader
        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(fillerMarket), from1, 1, block.timestamp + 100),
                1,
                address(currency1),
                1000,
                0,
                address(0),
                0,
                0,
                0,
                address(limitOrderValidator),
                abi.encode(PerpLimitOrderValidationData(0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            vm.startPrank(from1);
            IPredyPool.TradeResult memory tradeResult2 = fillerMarket.executeOrder(
                signedOrder,
                settlement.getSettlementParams(normalSwapRoute, 2000, address(currency1), address(currency0), 0)
            );
            vm.stopPrank();

            assertEq(tradeResult2.payoff.perpEntryUpdate, -998);
            assertEq(tradeResult2.payoff.sqrtEntryUpdate, 0);
            assertEq(tradeResult2.payoff.perpPayoff, -6);
            assertEq(tradeResult2.payoff.sqrtPayoff, 0);
        }
    }

    // netting
    function testExecuteOrderSucceedsWithNetting() public {
        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
                1,
                address(currency1),
                -1000 * 1e4,
                2 * 1e8,
                address(0),
                0,
                0,
                0,
                address(limitOrderValidator),
                abi.encode(PerpLimitOrderValidationData(0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(
                signedOrder,
                settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0)
            );
        }

        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(fillerMarket), from1, 1, block.timestamp + 100),
                1,
                address(currency1),
                1000 * 1e4,
                0,
                address(0),
                0,
                0,
                0,
                address(limitOrderValidator),
                abi.encode(PerpLimitOrderValidationData(0, calculateLimitPrice(1200, 1000)))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(
                signedOrder,
                settlement.getSettlementParams(normalSwapRoute, 1200 * 1e4, address(currency1), address(currency0), 0)
            );
        }
    }

    // executeOrder succeeds with 0 amount
    function testExecuteOrderSucceedsWithZeroAmount() public {
        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
                1,
                address(currency1),
                -1000,
                2 * 1e6,
                address(0),
                0,
                0,
                0,
                address(limitOrderValidator),
                abi.encode(PerpLimitOrderValidationData(0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(
                signedOrder,
                settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0)
            );
        }

        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(fillerMarket), from1, 1, block.timestamp + 100),
                1,
                address(currency1),
                0,
                3 * 1e6,
                address(0),
                0,
                0,
                0,
                address(0),
                ""
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(
                signedOrder,
                settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0)
            );

            DataType.Vault memory vault = predyPool.getVault(1);

            assertEq(vault.margin, 5 * 1e6);
        }
    }

    // executeOrder succeeds with margin amount
    // executeOrder fails if withdrawn margin amount is too large

    // executeOrder succeeds with margin ratio
    // executeOrder fails if margin ratio is invalid

    // executeOrder fails if deadline passed
    function testExecuteOrderFails_IfDeadlinePassed() public {
        PerpOrder memory order = PerpOrder(
            OrderInfo(address(fillerMarket), from1, 0, 1),
            1,
            address(currency1),
            1000,
            2 * 1e6,
            address(0),
            0,
            0,
            0,
            address(limitOrderValidator),
            abi.encode(PerpLimitOrderValidationData(0, calculateLimitPrice(1200, 1000)))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0), 0);

        vm.expectRevert();
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if signature is invalid
    function testExecuteOrderFails_IfSignerIsNotOwner() public {
        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0), 0);

        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(fillerMarket), from1, 0, block.timestamp),
                1,
                address(currency1),
                1000,
                2 * 1e6,
                address(0),
                0,
                0,
                0,
                address(limitOrderValidator),
                abi.encode(PerpLimitOrderValidationData(0, calculateLimitPrice(1200, 1000)))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(signedOrder, settlementData);
        }

        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(fillerMarket), from2, 0, block.timestamp),
                1,
                address(currency1),
                1000,
                0,
                address(0),
                0,
                0,
                0,
                address(limitOrderValidator),
                abi.encode(PerpLimitOrderValidationData(0, calculateLimitPrice(1200, 1000)))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            // vm.expectRevert(IFillerMarket.SignerIsNotVaultOwner.selector);
            vm.expectRevert();
            fillerMarket.executeOrder(signedOrder, settlementData);
        }
    }

    // executeOrder fails if nonce is invalid

    // executeOrder fails if price is greater than limit
    function testExecuteOrderFails_IfPriceIsGreaterThanLimit() public {
        PerpOrder memory order = PerpOrder(
            OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            1000,
            2 * 1e6,
            address(0),
            0,
            0,
            0,
            address(limitOrderValidator),
            abi.encode(PerpLimitOrderValidationData(0, calculateLimitPrice(999, 1000)))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0), 0);

        vm.expectRevert(PerpLimitOrderValidator.PriceGreaterThanLimit.selector);
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if price is less than limit
    function testExecuteOrderFails_IfPriceIsLessThanLimit() public {
        PerpOrder memory order = PerpOrder(
            OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            -1000,
            2 * 1e6,
            address(0),
            0,
            0,
            0,
            address(limitOrderValidator),
            abi.encode(PerpLimitOrderValidationData(0, calculateLimitPrice(1001, 1000)))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0);

        vm.expectRevert(PerpLimitOrderValidator.PriceLessThanLimit.selector);
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if filler pool is not enough
    // executeOrder fails if the vault is danger

    // executeOrder fails if pairId does not exist
}
