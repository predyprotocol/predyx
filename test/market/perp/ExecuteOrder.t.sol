// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";

contract TestPerpMarketExecuteOrder is TestPerpMarket {
    bytes normalSwapRoute;
    uint256 fromPrivateKey1;
    address from1;
    uint256 fromPrivateKey2;
    address from2;

    uint256 fillerPoolId;

    function setUp() public override {
        TestPerpMarket.setUp();

        normalSwapRoute = abi.encodePacked(address(currency0), uint24(500), address(currency1));

        fillerPoolId = fillerMarket.addFillerPool(pairId);

        fillerMarket.depositToFillerPool(1, 1e8);

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

    function testExecuteOrderFailedIfTraderOpens() public {
        GeneralOrder memory order = GeneralOrder(
            OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
            0,
            1,
            -1000,
            0,
            2 * 1e6,
            0,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0);

        vm.startPrank(from1);
        vm.expectRevert(PerpMarket.CallerIsNotFiller.selector);
        fillerMarket.executeOrder(fillerPoolId, signedOrder, settlementData);
        vm.stopPrank();
    }

    // executeOrder succeeds for open(pnl, interest, premium, borrow fee)
    function testExecuteOrderSucceedsForOpen() public {
        GeneralOrder memory order = GeneralOrder(
            OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
            0,
            1,
            -1000,
            0,
            2 * 1e6,
            0,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        PerpMarket.PerpTradeResult memory tradeResult = fillerMarket.executeOrder(
            fillerPoolId,
            signedOrder,
            settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0)
        );

        assertEq(tradeResult.entryUpdate, 998);
        assertEq(tradeResult.payoff, 0);
    }

    // netting
    function testExecuteOrderSucceedsWithNetting() public {
        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
                0,
                1,
                -1000 * 1e4,
                0,
                2 * 1e8,
                0,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(
                1,
                signedOrder,
                settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0)
            );
        }

        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from1, 1, block.timestamp + 100),
                1,
                1,
                1000 * 1e4,
                0,
                0,
                0,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(
                1,
                signedOrder,
                settlement.getSettlementParams(normalSwapRoute, 1200 * 1e4, address(currency1), address(currency0), 0)
            );
        }
    }

    // executeOrder succeeds for close
    function testExecuteOrderSucceedsForClosing() public {
        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
                0,
                1,
                -1000 * 1e4,
                0,
                2 * 1e8,
                0,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(
                1,
                signedOrder,
                settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0)
            );
        }

        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from1, 1, block.timestamp + 100),
                1,
                1,
                1000 * 1e4,
                0,
                0,
                0,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            vm.startPrank(from1);
            fillerMarket.executeOrder(
                1,
                signedOrder,
                settlement.getSettlementParams(normalSwapRoute, 1200 * 1e4, address(currency1), address(currency0), 0)
            );
            vm.stopPrank();
        }
    }

    // executeOrder fails if close and user margin is negative
    function testExecuteOrderFailsIfMarginIsNegative() public {
        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
                0,
                1,
                -1000 * 1e4,
                0,
                210000,
                0,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(
                1,
                signedOrder,
                settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0)
            );
        }

        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from1, 1, block.timestamp + 100),
                1,
                1,
                1000 * 1e4,
                0,
                0,
                0,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1500, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            ISettlement.SettlementData memory settlementData =
                directSettlement.getSettlementParams(address(this), address(currency1), address(currency0), 12000);

            vm.startPrank(from1);
            vm.expectRevert(PerpMarket.UserMarginIsNegative.selector);
            fillerMarket.executeOrder(1, signedOrder, settlementData);
            vm.stopPrank();
        }
    }

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
        GeneralOrder memory order = GeneralOrder(
            OrderInfo(address(fillerMarket), from1, 0, 1),
            1,
            1,
            1000,
            0,
            2 * 1e6,
            0,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0), 0);

        vm.expectRevert();
        fillerMarket.executeOrder(1, signedOrder, settlementData);
    }

    // executeOrder fails if signature is invalid
    function testExecuteOrderFails_IfSignerIsNotOwner() public {
        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0), 0);

        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from1, 0, block.timestamp),
                0,
                1,
                1000,
                0,
                2 * 1e6,
                0,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(fillerPoolId, signedOrder, settlementData);
        }

        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from2, 0, block.timestamp),
                1,
                1,
                1000,
                0,
                0,
                0,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1200, 1000), 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey2);

            vm.expectRevert(IFillerMarket.SignerIsNotVaultOwner.selector);
            fillerMarket.executeOrder(fillerPoolId, signedOrder, settlementData);
        }
    }

    // executeOrder fails if nonce is invalid

    // executeOrder fails if price is greater than limit
    function testExecuteOrderFails_IfPriceIsGreaterThanLimit() public {
        GeneralOrder memory order = GeneralOrder(
            OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
            0,
            1,
            1000,
            0,
            2 * 1e6,
            0,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(999, 1000), 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0), 0);

        vm.expectRevert(GeneralOrderLib.PriceGreaterThanLimit.selector);
        fillerMarket.executeOrder(1, signedOrder, settlementData);
    }

    // executeOrder fails if price is less than limit
    function testExecuteOrderFails_IfPriceIsLessThanLimit() public {
        GeneralOrder memory order = GeneralOrder(
            OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
            0,
            1,
            -1000,
            0,
            2 * 1e6,
            0,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, calculateLimitPrice(1001, 1000), 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0);

        vm.expectRevert(GeneralOrderLib.PriceLessThanLimit.selector);
        fillerMarket.executeOrder(1, signedOrder, settlementData);
    }

    // executeOrder fails if filler pool is not enough
    function testExecuteOrderFailedIfFillerPoolIsNotEnough() public {
        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
                0,
                1,
                -1e8,
                0,
                5 * 1e6,
                0,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            ISettlement.SettlementData memory settlementData =
                settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0);

            // vm.expectRevert(PerpMarket.FillerPoolIsNotSafe.selector);
            fillerMarket.executeOrder(fillerPoolId, signedOrder, settlementData);
        }

        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from2, 0, block.timestamp + 100),
                0,
                1,
                1e8,
                0,
                5 * 1e6,
                0,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey2);

            ISettlement.SettlementData memory settlementData =
                settlement.getSettlementParams(normalSwapRoute, 1e10, address(currency1), address(currency0), 0);

            fillerMarket.executeOrder(fillerPoolId, signedOrder, settlementData);
        }

        fillerMarket.withdrawFromFillerPool(1, 89 * 1e6);

        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from2, 1, block.timestamp + 100),
                0,
                1,
                1e8,
                0,
                5 * 1e6,
                0,
                address(limitOrderValidator),
                abi.encode(LimitOrderValidationData(0, 0, 0, 0))
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey2);

            ISettlement.SettlementData memory settlementData =
                settlement.getSettlementParams(normalSwapRoute, 1e10, address(currency1), address(currency0), 0);

            vm.expectRevert(PerpMarket.FillerPoolIsNotSafe.selector);
            fillerMarket.executeOrder(fillerPoolId, signedOrder, settlementData);
        }
    }

    // executeOrder fails if the position is danger
    function testExecuteOrderFailedIfPositionIsDanger() public {
        GeneralOrder memory order = GeneralOrder(
            OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
            0,
            1,
            -1e6,
            0,
            1e4,
            0,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0);

        vm.expectRevert(bytes("DANGER"));
        fillerMarket.executeOrder(fillerPoolId, signedOrder, settlementData);
    }

    // executeOrder fails if pairId does not exist
}
