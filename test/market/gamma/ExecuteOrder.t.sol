// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import "forge-std/console2.sol";

contract TestGammaExecuteOrder is TestMarket {
    bytes normalSwapRoute;
    uint256 fromPrivateKey1;
    address from1;
    uint256 fromPrivateKey2;
    address from2;

    function setUp() public override {
        TestMarket.setUp();

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
        GammaOrder memory order = GammaOrder(
            OrderInfo(address(fillerMarket), from1, address(0), 0, block.timestamp + 100),
            0,
            1,
            address(currency1),
            -1000,
            900,
            2 * 1e6,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IPredyPool.TradeResult memory tradeResult = fillerMarket.executeOrder(
            signedOrder, settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0)
        );

        assertEq(tradeResult.payoff.perpEntryUpdate, 980);
        assertEq(tradeResult.payoff.sqrtEntryUpdate, -1782);
        assertEq(tradeResult.payoff.perpPayoff, 0);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
    }

    // netting
    function testExecuteOrderSucceedsWithNetting() public {
        {
            GammaOrder memory order = GammaOrder(
                OrderInfo(address(fillerMarket), from1, address(0), 0, block.timestamp + 100),
                0,
                1,
                address(currency1),
                -1000 * 1e4,
                0,
                2 * 1e8,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(
                signedOrder,
                settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0)
            );
        }

        {
            GammaOrder memory order = GammaOrder(
                OrderInfo(address(fillerMarket), from1, address(0), 1, block.timestamp + 100),
                1,
                1,
                address(currency1),
                1000 * 1e4,
                0,
                0,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(
                signedOrder,
                settlement.getSettlementParams(normalSwapRoute, 1200 * 1e4, address(currency1), address(currency0), 0)
            );
        }
    }

    // executeOrder succeeds for close
    // executeOrder succeeds with market order
    // executeOrder succeeds with limit order
    // executeOrder succeeds with stop order

    // executeOrder succeeds with 0 amount

    // executeOrder succeeds with margin amount
    // executeOrder fails if withdrawn margin amount is too large

    // executeOrder succeeds with margin ratio
    // executeOrder fails if margin ratio is invalid

    // executeOrder fails if deadline passed
    function testExecuteOrderFails_IfDeadlinePassed() public {
        GammaOrder memory order = GammaOrder(
            OrderInfo(address(fillerMarket), from1, address(0), 0, 1),
            1,
            1,
            address(currency1),
            1000,
            0,
            2 * 1e6,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
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
            GammaOrder memory order = GammaOrder(
                OrderInfo(address(fillerMarket), from1, address(0), 0, block.timestamp),
                0,
                1,
                address(currency1),
                1000,
                0,
                2 * 1e6,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(signedOrder, settlementData);
        }

        {
            GammaOrder memory order = GammaOrder(
                OrderInfo(address(fillerMarket), from2, address(0), 0, block.timestamp),
                1,
                1,
                address(currency1),
                1000,
                0,
                0,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey2);

            vm.expectRevert(IFillerMarket.SignerIsNotVaultOwner.selector);
            fillerMarket.executeOrder(signedOrder, settlementData);
        }
    }

    // executeOrder fails if nonce is invalid

    // executeOrder fails if price is greater than limit
    function testExecuteOrderFails_IfPriceIsGreaterThanLimit() public {
        GammaOrder memory order = GammaOrder(
            OrderInfo(address(fillerMarket), from1, address(0), 0, block.timestamp + 100),
            0,
            1,
            address(currency1),
            1000,
            0,
            2 * 1e6,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(999, 1000), 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0), 0);

        vm.expectRevert(LimitOrderValidator.PriceGreaterThanLimit.selector);
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if price is less than limit
    function testExecuteOrderFails_IfPriceIsLessThanLimit() public {
        GammaOrder memory order = GammaOrder(
            OrderInfo(address(fillerMarket), from1, address(0), 0, block.timestamp + 100),
            0,
            1,
            address(currency1),
            -1000,
            0,
            2 * 1e6,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1001, 1000), 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0);

        vm.expectRevert(LimitOrderValidator.PriceLessThanLimit.selector);
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if filler pool is not enough
    // executeOrder fails if the vault is danger

    // executeOrder fails if pairId does not exist
}
