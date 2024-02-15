// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import {OrderInfo} from "../../../src/libraries/orders/OrderInfoLib.sol";
import {Bps} from "../../../src/libraries/math/Bps.sol";
import {PerpMarketV1} from "../../../src/markets/perp/PerpMarketV1.sol";

contract TestPerpExecuteOrder is TestPerpMarket {
    bytes normalSwapRoute;
    uint256 fromPrivateKey1;
    address from1;
    uint256 fromPrivateKey2;
    address from2;

    function setUp() public override {
        TestPerpMarket.setUp();

        registerPair(address(currency1), address(0));
        perpMarket.updateQuoteTokenMap(1);

        predyPool.supply(1, true, 1e10);
        predyPool.supply(1, false, 1e10);

        normalSwapRoute = abi.encodePacked(address(currency0), uint24(500), address(currency1));

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
                OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
                1,
                address(currency1),
                -1000,
                2 * 1e6,
                0,
                0,
                0,
                2,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(0);

            vm.startPrank(from1);
            vm.expectRevert(IFillerMarket.CallerIsNotFiller.selector);
            perpMarket.executeOrder(signedOrder, settlementData);
            vm.stopPrank();

            IPredyPool.TradeResult memory tradeResult = perpMarket.executeOrder(signedOrder, settlementData);

            assertEq(tradeResult.payoff.perpEntryUpdate, 998);
            assertEq(tradeResult.payoff.sqrtEntryUpdate, 0);
            assertEq(tradeResult.payoff.perpPayoff, 0);
            assertEq(tradeResult.payoff.sqrtPayoff, 0);
        }

        // Close position by trader
        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(perpMarket), from1, 1, block.timestamp + 100),
                1,
                address(currency1),
                1000,
                0,
                0,
                0,
                0,
                2,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            vm.startPrank(from1);
            IPredyPool.TradeResult memory tradeResult2 =
                perpMarket.executeOrder(signedOrder, _getUniSettlementData(2000));
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
                OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
                1,
                address(currency1),
                -1000 * 1e4,
                2 * 1e8,
                0,
                0,
                0,
                2,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            perpMarket.executeOrder(signedOrder, _getUniSettlementData(0));
        }

        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(perpMarket), from1, 1, block.timestamp + 100),
                1,
                address(currency1),
                1000 * 1e4,
                0,
                0,
                0,
                0,
                2,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            perpMarket.executeOrder(signedOrder, _getUniSettlementData(1200 * 1e4));
        }
    }

    // executeOrder succeeds with 0 amount
    function testExecuteOrderSucceedsWithZeroAmount() public {
        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
                1,
                address(currency1),
                -1000,
                2 * 1e6,
                0,
                0,
                0,
                2,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            perpMarket.executeOrder(signedOrder, _getUniSettlementData(0));
        }

        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(perpMarket), from1, 1, block.timestamp + 100),
                1,
                address(currency1),
                0,
                3 * 1e6,
                0,
                0,
                0,
                2,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            perpMarket.executeOrder(signedOrder, _getUniSettlementData(0));

            DataType.Vault memory vault = predyPool.getVault(1);

            assertEq(vault.margin, 5 * 1e6);
        }
    }

    function testAvoidFreeze() public {
        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
                1,
                address(currency1),
                -1000,
                2 * 1e6,
                0,
                0,
                0,
                2,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            perpMarket.executeOrder(signedOrder, _getUniSettlementData(0));
        }

        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(perpMarket), from1, 1, block.timestamp + 100),
                1,
                address(currency1),
                1000,
                3 * 1e6,
                0,
                0,
                0,
                2,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(1200);

            vm.expectRevert(PerpMarketV1.UpdateMarginMustNotBePositive.selector);
            perpMarket.executeOrder(signedOrder, settlementData);
        }
    }

    // executeOrder fails if deadline passed
    function testExecuteOrderFails_IfDeadlinePassed() public {
        PerpOrder memory order = PerpOrder(
            OrderInfo(address(perpMarket), from1, 0, 1),
            1,
            address(currency1),
            1000,
            2 * 1e6,
            0,
            0,
            0,
            2,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(1500);

        vm.expectRevert();
        perpMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if signature is invalid
    function testExecuteOrderFails_IfSignerIsNotOwner() public {
        IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(1500);

        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(perpMarket), from1, 0, block.timestamp),
                1,
                address(currency1),
                1000,
                2 * 1e6,
                0,
                0,
                0,
                2,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            perpMarket.executeOrder(signedOrder, settlementData);
        }

        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(perpMarket), from2, 0, block.timestamp),
                1,
                address(currency1),
                1000,
                0,
                0,
                0,
                0,
                2,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            // vm.expectRevert(IFillerMarket.SignerIsNotVaultOwner.selector);
            vm.expectRevert();
            perpMarket.executeOrder(signedOrder, settlementData);
        }
    }

    // executeOrder fails if price is greater than limit
    function testExecuteOrderFails_IfPriceIsGreaterThanLimit() public {
        PerpOrder memory order = PerpOrder(
            OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            1000,
            2 * 1e6,
            0,
            0,
            0,
            2,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(999, 1000), 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(1500);

        vm.expectRevert(LimitOrderValidator.PriceGreaterThanLimit.selector);
        perpMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if price is less than limit
    function testExecuteOrderFails_IfPriceIsLessThanLimit() public {
        PerpOrder memory order = PerpOrder(
            OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            -1000,
            2 * 1e6,
            0,
            0,
            0,
            2,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1001, 1000), 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(0);

        vm.expectRevert(LimitOrderValidator.PriceLessThanLimit.selector);
        perpMarket.executeOrder(signedOrder, settlementData);
    }

    function testExecuteOrderSucceedsForTPSL() public {
        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
                1,
                address(currency1),
                -1000 * 1e4,
                2 * 1e8,
                0,
                0,
                0,
                2,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            perpMarket.executeOrder(signedOrder, _getUniSettlementData(0));
        }

        {
            PerpOrder memory order = PerpOrder(
                OrderInfo(address(perpMarket), from1, 1, block.timestamp + 100),
                1,
                address(currency1),
                0,
                0,
                Constants.Q96 * 10 / 11,
                Constants.Q96 * 11 / 10,
                10000,
                2,
                address(0),
                bytes("")
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            perpMarket.executeOrder(signedOrder, _getUniSettlementData(1200 * 1e4));
        }

        (, uint256 takeProfitPrice, uint256 stopLossPrice, uint64 slippageTolerance, uint8 leverage) =
            perpMarket.userPositions(from1, 1);

        assertEq(takeProfitPrice, Constants.Q96 * 10 / 11);
        assertEq(stopLossPrice, Constants.Q96 * 11 / 10);
        assertEq(slippageTolerance, 10000);
        assertEq(leverage, 2);
    }

    // decode
    function testExecuteOrderV2Succeeds() public {
        PerpOrder memory order = PerpOrder(
            OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            -1000,
            2 * 1e6,
            0,
            0,
            0,
            2,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, 0, 0))
        );

        PerpOrderV2 memory optOrder = PerpOrderV2(
            from1,
            order.info.nonce,
            encodePerpOrderParams(uint64(order.info.deadline), uint64(order.pairId), uint8(order.leverage)),
            order.tradeAmount,
            order.marginAmount,
            order.validatorAddress,
            order.validationData
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(0);

        IPredyPool.TradeResult memory tradeResult = perpMarket.executeOrderV2(optOrder, signedOrder.sig, settlementData);

        assertEq(tradeResult.payoff.perpEntryUpdate, 998);
        assertEq(tradeResult.payoff.sqrtEntryUpdate, 0);
        assertEq(tradeResult.payoff.perpPayoff, 0);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
    }
}
