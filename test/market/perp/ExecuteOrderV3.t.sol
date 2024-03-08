// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import {OrderInfo} from "../../../src/libraries/orders/OrderInfoLib.sol";
import {Bps} from "../../../src/libraries/math/Bps.sol";
import {PerpMarketV1} from "../../../src/markets/perp/PerpMarketV1.sol";
import {PerpOrderV3} from "../../../src/markets/perp/PerpOrderV3.sol";
import {PerpMarketLib} from "../../../src/markets/perp/PerpMarketLib.sol";
import {MockPriceFeed} from "../../mocks/MockPriceFeed.sol";

contract TestPerpExecuteOrderV3 is TestPerpMarket {
    bytes normalSwapRoute;
    uint256 fromPrivateKey1;
    address from1;
    uint256 fromPrivateKey2;
    address from2;

    MockPriceFeed private _priceFeed;

    function setUp() public override {
        TestPerpMarket.setUp();

        _priceFeed = new MockPriceFeed();

        _priceFeed.setSqrtPrice(2 ** 96);

        registerPair(address(currency1), address(_priceFeed));
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

    // executeOrderV3 succeeds for open(pnl, interest, premium, borrow fee)
    function testExecuteOrderV3SucceedsForOpen() public {
        uint256 balance0 = currency1.balanceOf(from1);

        {
            PerpOrderV3 memory order = PerpOrderV3(
                OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
                1,
                address(currency1),
                -2 * 1e6,
                2 * 1e6 * 101 / 100,
                0,
                0,
                1,
                abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(0);

            vm.startPrank(from1);
            vm.expectRevert(IFillerMarket.CallerIsNotFiller.selector);
            perpMarket.executeOrderV3(signedOrder, settlementData);
            vm.stopPrank();

            IPredyPool.TradeResult memory tradeResult = perpMarket.executeOrderV3(signedOrder, settlementData);

            assertEq(tradeResult.payoff.perpEntryUpdate, 1998999);
            assertEq(tradeResult.payoff.sqrtEntryUpdate, 0);
            assertEq(tradeResult.payoff.perpPayoff, 0);
            assertEq(tradeResult.payoff.sqrtPayoff, 0);
        }

        uint256 balance1 = currency1.balanceOf(from1);

        // Close position by trader
        {
            PerpOrderV3 memory order = PerpOrderV3(
                OrderInfo(address(perpMarket), from1, 1, block.timestamp + 100),
                1,
                address(currency1),
                2 * 1e6,
                0,
                0,
                0,
                2,
                abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            vm.startPrank(from1);
            IPredyPool.TradeResult memory tradeResult2 =
                perpMarket.executeOrderV3(signedOrder, _getUniSettlementData(2 * 1e6 * 101 / 100));
            vm.stopPrank();

            assertEq(tradeResult2.payoff.perpEntryUpdate, -1998999);
            assertEq(tradeResult2.payoff.sqrtEntryUpdate, 0);
            assertEq(tradeResult2.payoff.perpPayoff, -2004);
            assertEq(tradeResult2.payoff.sqrtPayoff, 0);
        }

        uint256 balance2 = currency1.balanceOf(from1);

        assertEq(balance0 - balance1, 2000000);
        assertEq(balance2 - balance1, 1997996);
    }

    // netting
    function testExecuteOrderSucceedsWithNetting() public {
        {
            PerpOrderV3 memory order = PerpOrderV3(
                OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
                1,
                address(currency1),
                -1000 * 1e4,
                2 * 1e8,
                0,
                0,
                2,
                abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            perpMarket.executeOrderV3(signedOrder, _getUniSettlementData(0));
        }

        {
            PerpOrderV3 memory order = PerpOrderV3(
                OrderInfo(address(perpMarket), from1, 1, block.timestamp + 100),
                1,
                address(currency1),
                1000 * 1e4,
                calculateLimitPrice(1200, 1000),
                0,
                0,
                2,
                abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            perpMarket.executeOrderV3(signedOrder, _getUniSettlementData(1200 * 1e4));
        }
    }

    // executeOrderV3 failed if mount is 0
    function testExecuteOrderFailedBecauseAmoutIsZero() public {
        PerpOrderV3 memory order = PerpOrderV3(
            OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            0,
            1e7,
            0,
            0,
            2,
            abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(0);

        vm.expectRevert(PerpMarketV1.AmountIsZero.selector);
        perpMarket.executeOrderV3(signedOrder, settlementData);
    }

    function testAvoidFreeze() public {
        {
            PerpOrderV3 memory order = PerpOrderV3(
                OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
                1,
                address(currency1),
                -1e7,
                1e7,
                0,
                0,
                2,
                abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            perpMarket.executeOrderV3(signedOrder, _getUniSettlementData(0));
        }

        {
            PerpOrderV3 memory order = PerpOrderV3(
                OrderInfo(address(perpMarket), from1, 1, block.timestamp + 100),
                1,
                address(currency1),
                1e7,
                1e7,
                0,
                0,
                2,
                abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(12 * 1e6);

            perpMarket.executeOrderV3(signedOrder, settlementData);
        }

        assertEq(currency1.balanceOf(address(perpMarket)), 0);
    }

    // executeOrderV3 fails if deadline passed
    function testExecuteOrderFails_IfDeadlinePassed() public {
        PerpOrderV3 memory order = PerpOrderV3(
            OrderInfo(address(perpMarket), from1, 0, 1),
            1,
            address(currency1),
            1000,
            2 * 1e6,
            calculateLimitPrice(1200, 1000),
            0,
            2,
            abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(1500);

        vm.expectRevert();
        perpMarket.executeOrderV3(signedOrder, settlementData);
    }

    // executeOrderV3 fails if signature is invalid
    function testExecuteOrderFails_IfSignerIsNotOwner() public {
        IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(15 * 1e6);

        {
            PerpOrderV3 memory order = PerpOrderV3(
                OrderInfo(address(perpMarket), from1, 0, block.timestamp),
                1,
                address(currency1),
                1e7,
                1e7,
                calculateLimitPrice(1200, 1000),
                0,
                2,
                abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            perpMarket.executeOrderV3(signedOrder, settlementData);
        }

        {
            PerpOrderV3 memory order = PerpOrderV3(
                OrderInfo(address(perpMarket), from2, 0, block.timestamp),
                1,
                address(currency1),
                1e7,
                0,
                calculateLimitPrice(1200, 1000),
                0,
                2,
                abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            // vm.expectRevert(IFillerMarket.SignerIsNotVaultOwner.selector);
            vm.expectRevert();
            perpMarket.executeOrderV3(signedOrder, settlementData);
        }
    }

    // executeOrderV3 fails if price is greater than limit
    function testExecuteOrderFails_IfPriceIsGreaterThanLimit() public {
        PerpOrderV3 memory order = PerpOrderV3(
            OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            1e7,
            1e7,
            calculateLimitPrice(999, 1000),
            0,
            2,
            abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(15 * 1e6);

        vm.expectRevert(PerpMarketLib.LimitPriceDoesNotMatch.selector);
        perpMarket.executeOrderV3(signedOrder, settlementData);
    }

    // executeOrderV3 fails if price is less than limit
    function testExecuteOrderFails_IfPriceIsLessThanLimit() public {
        PerpOrderV3 memory order = PerpOrderV3(
            OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            -1e7,
            1e7,
            calculateLimitPrice(1001, 1000),
            0,
            2,
            abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(0);

        vm.expectRevert(PerpMarketLib.LimitPriceDoesNotMatch.selector);
        perpMarket.executeOrderV3(signedOrder, settlementData);
    }

    // executeOrderV3 fails if price is less than stop price
    function testExecuteOrderFailsIfPriceIsLessThanStopPrice() public {
        PerpOrderV3 memory order = PerpOrderV3(
            OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            1e7,
            1e7,
            0,
            calculateLimitPrice(1001, 1000),
            2,
            abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(15 * 1e6);

        vm.expectRevert(PerpMarketLib.StopPriceDoesNotMatch.selector);
        perpMarket.executeOrderV3(signedOrder, settlementData);
    }

    // executeOrderV3 fails if price is greater than stop price
    function testExecuteOrderFailsIfPriceIsGreaterThanStopPrice() public {
        PerpOrderV3 memory order = PerpOrderV3(
            OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            -1e7,
            1e7,
            0,
            calculateLimitPrice(999, 1000),
            2,
            abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(0);

        vm.expectRevert(PerpMarketLib.StopPriceDoesNotMatch.selector);
        perpMarket.executeOrderV3(signedOrder, settlementData);
    }
}
