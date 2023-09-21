// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {GeneralOrderLib} from "../../src/libraries/market/GeneralOrderLib.sol";
import {SigUtils} from "../utils/SigUtils.sol";
import "forge-std/console2.sol";

contract TestExecuteOrder is TestMarket, SigUtils {
    using GeneralOrderLib for GeneralOrder;

    bytes normalSwapRoute;
    uint256 fromPrivateKey1;
    address from1;
    uint256 fromPrivateKey2;
    address from2;
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public override {
        TestMarket.setUp();

        registerPair(address(currency1));

        predyPool.supply(1, true, 1e8);
        predyPool.supply(1, false, 1e8);

        normalSwapRoute = abi.encodePacked(address(currency0), uint24(500), address(currency1));

        fillerMarket.depositToFillerPool(100 * 1e6);

        fromPrivateKey1 = 0x12341234;
        from1 = vm.addr(fromPrivateKey1);
        fromPrivateKey2 = 0x1235678;
        from2 = vm.addr(fromPrivateKey2);
        DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();

        currency1.mint(from1, type(uint128).max);
        currency1.mint(from2, type(uint128).max);

        vm.prank(from1);
        currency1.approve(address(permit2), type(uint256).max);

        vm.prank(from2);
        currency1.approve(address(permit2), type(uint256).max);
    }

    function _toPermit(GeneralOrder memory order)
        internal
        view
        returns (ISignatureTransfer.PermitTransferFrom memory)
    {
        uint256 amount = order.marginAmount > 0 ? uint256(order.marginAmount) : 0;

        return ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(currency1), amount: amount}),
            nonce: order.info.nonce,
            deadline: order.info.deadline
        });
    }

    function _createSignedOrder(GeneralOrder memory marketOrder, uint256 fromPrivateKey)
        internal
        view
        returns (IFillerMarket.SignedOrder memory signedOrder)
    {
        bytes32 witness = marketOrder.hash();

        bytes memory sig = getPermitSignature(
            fromPrivateKey,
            _toPermit(marketOrder),
            address(fillerMarket),
            GeneralOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        signedOrder = IFillerMarket.SignedOrder(abi.encode(marketOrder), sig);
    }

    // executeOrder succeeds for open(pnl, interest, premium, borrow fee)
    function testExecuteOrderSucceedsForOpen() public {
        GeneralOrder memory order = GeneralOrder(
            OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100), 0, 1, -1000, 900, 0, 0, 0, 0, 1e5, 0
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IPredyPool.TradeResult memory tradeResult = fillerMarket.executeOrder(
            signedOrder,
            abi.encode(BaseMarket.SettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0))
        );

        assertEq(tradeResult.payoff.perpEntryUpdate, 980);
        assertEq(tradeResult.payoff.sqrtEntryUpdate, -1782);
        assertEq(tradeResult.payoff.perpPayoff, 0);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
    }

    // netting
    function testExecuteOrderSucceedsWithNetting() public {
        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100), 0, 1, -1000, 0, 0, 0, 0, 0, 1e5, 0
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(
                signedOrder,
                abi.encode(BaseMarket.SettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0))
            );
        }

        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from1, 1, block.timestamp + 100), 1, 1, 1000, 0, 0, 0, 1200, 0, 1e5, 0
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(
                signedOrder,
                abi.encode(
                    BaseMarket.SettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0), 0)
                )
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
        GeneralOrder memory order =
            GeneralOrder(OrderInfo(address(fillerMarket), from1, 0, 1), 1, 1, 1000, 0, 0, 0, 1200, 0, 1e5, 0);

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        bytes memory settlementData =
            abi.encode(BaseMarket.SettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0), 0));

        vm.expectRevert();
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if signature is invalid
    function testExecuteOrderFails_IfSignerIsNotOwner() public {
        bytes memory settlementData =
            abi.encode(BaseMarket.SettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0), 0));

        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from1, 0, block.timestamp), 0, 1, 1000, 0, 0, 0, 1200, 0, 1e5, 0
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

            fillerMarket.executeOrder(signedOrder, settlementData);
        }

        {
            GeneralOrder memory order = GeneralOrder(
                OrderInfo(address(fillerMarket), from2, 0, block.timestamp), 1, 1, 1000, 0, 0, 0, 1200, 0, 1e5, 0
            );

            IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey2);

            vm.expectRevert(IFillerMarket.SignerIsNotVaultOwner.selector);
            fillerMarket.executeOrder(signedOrder, settlementData);
        }
    }

    // executeOrder fails if nonce is invalid

    // executeOrder fails if price is greater than limit
    function testExecuteOrderFails_IfPriceIsGreaterThanLimit() public {
        GeneralOrder memory order = GeneralOrder(
            OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100), 0, 1, 1000, 0, 0, 0, 999, 0, 1e5, 0
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        bytes memory settlementData =
            abi.encode(BaseMarket.SettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0), 0));

        vm.expectRevert(GeneralOrderLib.PriceGreaterThanLimit.selector);
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if price is less than limit
    function testExecuteOrderFails_IfPriceIsLessThanLimit() public {
        GeneralOrder memory order = GeneralOrder(
            OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100), 0, 1, -1000, 0, 0, 0, 1001, 0, 1e5, 0
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        bytes memory settlementData =
            abi.encode(BaseMarket.SettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0));

        vm.expectRevert(GeneralOrderLib.PriceLessThanLimit.selector);
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if filler pool is not enough
    // executeOrder fails if the vault is danger

    // executeOrder fails if pairId does not exist
}
