// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import {OrderInfo} from "../../../src/libraries/orders/OrderInfoLib.sol";
import {Constants} from "../../../src/libraries/Constants.sol";

contract TestGammaExecuteOrder is TestGammaMarket {
    bytes normalSwapRoute;
    uint256 fromPrivateKey1;
    address from1;
    uint256 fromPrivateKey2;
    address from2;

    function setUp() public override {
        TestGammaMarket.setUp();

        registerPair(address(currency1), address(0));
        gammaTradeMarket.updateQuoteTokenMap(1);

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
        GammaOrder memory order = GammaOrder(
            OrderInfo(address(gammaTradeMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            -1000,
            900,
            2 * 1e6,
            12 hours,
            0,
            1000,
            1000,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IPredyPool.TradeResult memory tradeResult =
            gammaTradeMarket.executeOrder(signedOrder, _getSettlementData(Constants.Q96));

        assertEq(tradeResult.payoff.perpEntryUpdate, 1000);
        assertEq(tradeResult.payoff.sqrtEntryUpdate, -1800);
        assertEq(tradeResult.payoff.perpPayoff, 0);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
    }

    // netting
    function testExecuteOrderSucceedsWithNetting() public {
        {
            GammaOrder memory order = GammaOrder(
                OrderInfo(address(gammaTradeMarket), from1, 0, block.timestamp + 100),
                1,
                address(currency1),
                -1000 * 1e4,
                0,
                2 * 1e8,
                12 hours,
                0,
                1000,
                1000,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            gammaTradeMarket.executeOrder(signedOrder, _getSettlementData(Constants.Q96));
        }

        {
            GammaOrder memory order = GammaOrder(
                OrderInfo(address(gammaTradeMarket), from1, 1, block.timestamp + 100),
                1,
                address(currency1),
                1000 * 1e4,
                0,
                0,
                12 hours,
                0,
                1000,
                1000,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            gammaTradeMarket.executeOrder(signedOrder, _getSettlementData(Constants.Q96));
        }
    }

    // executeOrder fails if deadline passed
    function testExecuteOrderFails_IfDeadlinePassed() public {
        GammaOrder memory order = GammaOrder(
            OrderInfo(address(gammaTradeMarket), from1, 0, 1),
            1,
            address(currency1),
            1000,
            0,
            2 * 1e6,
            12 hours,
            0,
            1000,
            1000,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IFillerMarket.SettlementParams memory settlementData = _getSettlementData(Constants.Q96);

        vm.expectRevert();
        gammaTradeMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if signature is invalid
    function testExecuteOrderFails_IfSignerIsNotOwner() public {
        IFillerMarket.SettlementParams memory settlementData = _getSettlementData(Constants.Q96);

        {
            GammaOrder memory order = GammaOrder(
                OrderInfo(address(gammaTradeMarket), from1, 0, block.timestamp),
                1,
                address(currency1),
                1000,
                0,
                2 * 1e6,
                12 hours,
                0,
                1000,
                1000,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            gammaTradeMarket.executeOrder(signedOrder, settlementData);
        }

        {
            GammaOrder memory order = GammaOrder(
                OrderInfo(address(gammaTradeMarket), from2, 0, block.timestamp),
                1,
                address(currency1),
                1000,
                0,
                0,
                12 hours,
                0,
                1000,
                1000,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey2);

            vm.expectRevert();
            gammaTradeMarket.executeOrder(signedOrder, settlementData);
        }
    }

    // executeOrder fails if price is greater than limit
    function testExecuteOrderFails_IfPriceIsGreaterThanLimit() public {
        GammaOrder memory order = GammaOrder(
            OrderInfo(address(gammaTradeMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            1000,
            0,
            2 * 1e6,
            12 hours,
            0,
            1000,
            1000,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(999, 1000), 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IFillerMarket.SettlementParams memory settlementData = _getSettlementData(Constants.Q96);

        vm.expectRevert(LimitOrderValidator.PriceGreaterThanLimit.selector);
        gammaTradeMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if price is less than limit
    function testExecuteOrderFails_IfPriceIsLessThanLimit() public {
        GammaOrder memory order = GammaOrder(
            OrderInfo(address(gammaTradeMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            -1000,
            0,
            2 * 1e6,
            12 hours,
            0,
            1000,
            1000,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1001, 1000), 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IFillerMarket.SettlementParams memory settlementData = _getSettlementData(Constants.Q96);

        vm.expectRevert(LimitOrderValidator.PriceLessThanLimit.selector);
        gammaTradeMarket.executeOrder(signedOrder, settlementData);
    }
}
