// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {MarketOrderLib} from "../../src/libraries/market/MarketOrderLib.sol";
import {SigUtils} from "../utils/SigUtils.sol";
import "forge-std/console2.sol";

contract TestExecuteOrder is TestMarket, SigUtils {
    using MarketOrderLib for MarketOrder;

    bytes normalSwapRoute;
    uint256 fromPrivateKey;
    address from;
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public override {
        TestMarket.setUp();

        registerPair(address(currency1));

        predyPool.supply(1, true, 1e8);
        predyPool.supply(1, false, 1e8);

        normalSwapRoute = abi.encodePacked(address(currency0), uint24(500), address(currency1));

        fillerMarket.depositToFillerPool(100 * 1e6);

        fromPrivateKey = 0x12341234;
        from = vm.addr(fromPrivateKey);
        DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();

        currency1.mint(from, type(uint128).max);

        vm.prank(from);
        currency1.approve(address(permit2), type(uint256).max);
    }

    function toPermit(MarketOrder memory order) internal view returns (ISignatureTransfer.PermitTransferFrom memory) {
        uint256 amount = order.marginAmount > 0 ? uint256(order.marginAmount) : 0;

        return ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(currency1), amount: amount}),
            nonce: order.info.nonce,
            deadline: order.info.deadline
        });
    }

    // executeOrder succeeds for open(pnl, interest, premium, borrow fee)
    function testExecuteOrderSucceedsForOpen() public {
        MarketOrder memory order = MarketOrder(
            OrderInfo(address(fillerMarket), from, 0, block.timestamp + 100, ""), 1, 1, -1000, 900, 0, 0, 1e5, 0
        );

        bytes32 witness = order.hash();

        bytes memory sig = getPermitSignature(
            fromPrivateKey,
            toPermit(order),
            address(fillerMarket),
            MarketOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        IFillerMarket.SignedOrder memory signedOrder = IFillerMarket.SignedOrder(abi.encode(order), sig);

        IPredyPool.TradeResult memory tradeResult = fillerMarket.executeOrder(
            signedOrder,
            abi.encode(FillerMarket.SettlementParams(normalSwapRoute, 0, address(currency1), address(currency0)))
        );

        assertEq(tradeResult.payoff.perpEntryUpdate, 980);
        assertEq(tradeResult.payoff.sqrtEntryUpdate, -1782);
        assertEq(tradeResult.payoff.perpPayoff, 0);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
    }

    // netting
    function testExecuteOrderSucceedsWithNetting() public {
        {
            MarketOrder memory order = MarketOrder(
                OrderInfo(address(fillerMarket), from, 0, block.timestamp + 100, ""), 1, 1, -1000, 0, 0, 0, 1e5, 0
            );

            bytes32 witness = order.hash();

            bytes memory sig = getPermitSignature(
                fromPrivateKey,
                toPermit(order),
                address(fillerMarket),
                MarketOrderLib.PERMIT2_ORDER_TYPE,
                witness,
                DOMAIN_SEPARATOR
            );

            IFillerMarket.SignedOrder memory signedOrder = IFillerMarket.SignedOrder(abi.encode(order), sig);

            fillerMarket.executeOrder(
                signedOrder,
                abi.encode(FillerMarket.SettlementParams(normalSwapRoute, 0, address(currency1), address(currency0)))
            );
        }

        {
            MarketOrder memory order = MarketOrder(
                OrderInfo(address(fillerMarket), from, 1, block.timestamp + 100, ""), 1, 1, 1000, 0, 1200, 0, 1e5, 0
            );

            bytes32 witness = order.hash();

            bytes memory sig = getPermitSignature(
                fromPrivateKey,
                toPermit(order),
                address(fillerMarket),
                MarketOrderLib.PERMIT2_ORDER_TYPE,
                witness,
                DOMAIN_SEPARATOR
            );

            IFillerMarket.SignedOrder memory signedOrder = IFillerMarket.SignedOrder(abi.encode(order), sig);

            fillerMarket.executeOrder(
                signedOrder,
                abi.encode(FillerMarket.SettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0)))
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
        MarketOrder memory order =
            MarketOrder(OrderInfo(address(fillerMarket), from, 0, 1, ""), 1, 1, 1000, 0, 1200, 0, 1e5, 0);

        bytes32 witness = order.hash();

        bytes memory sig = getPermitSignature(
            fromPrivateKey,
            toPermit(order),
            address(fillerMarket),
            MarketOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        IFillerMarket.SignedOrder memory signedOrder = IFillerMarket.SignedOrder(abi.encode(order), sig);
        bytes memory settlementData =
            abi.encode(FillerMarket.SettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0)));

        vm.expectRevert();
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if signature is invalid
    // executeOrder fails if nonce is invalid

    // executeOrder fails if price is greater than limit
    function testExecuteOrderFails_IfPriceIsGreaterThanLimit() public {
        MarketOrder memory order = MarketOrder(
            OrderInfo(address(fillerMarket), from, 0, block.timestamp + 100, ""), 1, 1, 1000, 0, 999, 0, 1e5, 0
        );

        bytes32 witness = order.hash();

        bytes memory sig = getPermitSignature(
            fromPrivateKey,
            toPermit(order),
            address(fillerMarket),
            MarketOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        IFillerMarket.SignedOrder memory signedOrder = IFillerMarket.SignedOrder(abi.encode(order), sig);

        bytes memory settlementData =
            abi.encode(FillerMarket.SettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0)));

        vm.expectRevert(IFillerMarket.PriceGreaterThanLimit.selector);
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if price is less than limit
    function testExecuteOrderFails_IfPriceIsLessThanLimit() public {
        MarketOrder memory order = MarketOrder(
            OrderInfo(address(fillerMarket), from, 0, block.timestamp + 100, ""), 1, 1, -1000, 0, 1001, 0, 1e5, 0
        );

        bytes32 witness = order.hash();

        bytes memory sig = getPermitSignature(
            fromPrivateKey,
            toPermit(order),
            address(fillerMarket),
            MarketOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        IFillerMarket.SignedOrder memory signedOrder = IFillerMarket.SignedOrder(abi.encode(order), sig);

        bytes memory settlementData =
            abi.encode(FillerMarket.SettlementParams(normalSwapRoute, 0, address(currency1), address(currency0)));

        vm.expectRevert(IFillerMarket.PriceLessThanLimit.selector);
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if filler pool is not enough
    // executeOrder fails if the vault is danger

    // executeOrder fails if pairId does not exist
}
