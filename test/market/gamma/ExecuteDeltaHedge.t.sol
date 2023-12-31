// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import {OrderInfo} from "../../../src/libraries/orders/OrderInfoLib.sol";
import {Constants} from "../../../src/libraries/Constants.sol";
import {MockPriceFeed} from "../../mocks/MockPriceFeed.sol";

contract TestGammaExecuteDeltaHedge is TestGammaMarket {
    bytes normalSwapRoute;
    uint256 fromPrivateKey1;
    address from1;
    uint256 fromPrivateKey2;
    address from2;
    MockPriceFeed mockPriceFeed;

    function setUp() public override {
        TestGammaMarket.setUp();

        mockPriceFeed = new MockPriceFeed();

        registerPair(address(currency1), address(mockPriceFeed));

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

        gammaTradeMarket.executeOrder(signedOrder, _getSettlementData(Constants.Q96));
    }

    function testCannotExecuteDeltaHedgeByTime() public {
        mockPriceFeed.setSqrtPrice(2 ** 96);

        vm.warp(block.timestamp + 10 hours);

        IFillerMarket.SettlementParams memory settlementParams = _getSettlementData(Constants.Q96);

        vm.expectRevert(GammaTradeMarket.HedgeTriggerNotMatched.selector);
        gammaTradeMarket.execDeltaHedge(from1, 1, settlementParams);
    }

    function testSucceedsExecuteDeltaHedgeByTime() public {
        mockPriceFeed.setSqrtPrice(2 ** 96);

        vm.warp(block.timestamp + 12 hours);

        gammaTradeMarket.execDeltaHedge(from1, 1, _getSettlementData(Constants.Q96));
    }
}
