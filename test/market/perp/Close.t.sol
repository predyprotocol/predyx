// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import {MockPriceFeed} from "../../mocks/MockPriceFeed.sol";
import {OrderInfo} from "../../../src/libraries/orders/OrderInfoLib.sol";

contract TestGammaClose is TestPerpMarket {
    bytes normalSwapRoute;
    uint256 fromPrivateKey1;
    address from1;
    uint256 fromPrivateKey2;
    address from2;
    MockPriceFeed mockPriceFeed;

    function setUp() public override {
        TestPerpMarket.setUp();

        mockPriceFeed = new MockPriceFeed();

        registerPair(address(currency1), address(mockPriceFeed));
        perpMarket.updateQuoteTokenMap(1);

        predyPool.supply(1, true, 1e10);
        predyPool.supply(1, false, 1e10);

        normalSwapRoute = abi.encodePacked(address(currency0), uint24(500), address(currency1));

        fromPrivateKey1 = 0x12341234;
        from1 = vm.addr(fromPrivateKey1);
        fromPrivateKey2 = 0x12341235;
        from2 = vm.addr(fromPrivateKey2);

        currency1.mint(from1, type(uint128).max);
        currency1.mint(from2, type(uint128).max);

        vm.prank(from1);
        currency1.approve(address(permit2), type(uint256).max);

        vm.prank(from2);
        currency1.approve(address(permit2), type(uint256).max);

        // currency0.approve(address(directSettlement), type(uint256).max);
        // currency1.approve(address(directSettlement), type(uint256).max);

        PerpOrder memory order1 = PerpOrder(
            OrderInfo(address(perpMarket), from1, 0, block.timestamp + 100),
            1,
            address(currency1),
            1000,
            2 * 1e6,
            101 * Constants.Q96 / 100,
            100 * Constants.Q96 / 101,
            5000,
            2,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder1 = _createSignedOrder(order1, fromPrivateKey1);

        PerpOrder memory order2 = PerpOrder(
            OrderInfo(address(perpMarket), from2, 1, block.timestamp + 100),
            1,
            address(currency1),
            1000,
            2 * 1e6,
            0,
            0,
            5000,
            2,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder2 = _createSignedOrder(order2, fromPrivateKey2);

        perpMarket.executeOrder(signedOrder1, _getSettlementData(Constants.Q96));

        perpMarket.executeOrder(signedOrder2, _getSettlementData(Constants.Q96));
    }

    function testCloseFails() public {
        mockPriceFeed.setSqrtPrice(2 ** 96);

        IFillerMarket.SettlementParams memory settlementData = _getSettlementData(Constants.Q96);

        vm.expectRevert();
        perpMarket.close(from1, 1, settlementData);
    }

    function testCloseFailsIfTPNotSet() public {
        mockPriceFeed.setSqrtPrice(1011 * Constants.Q96 / 1000);

        IFillerMarket.SettlementParams memory settlementData = _getSettlementData(Constants.Q96 * 10220 / 10000);

        vm.expectRevert(PerpMarket.TPSLConditionDoesNotMatch.selector);
        perpMarket.close(from2, 1, settlementData);
    }

    function testCloseFailsIfSLNotSet() public {
        mockPriceFeed.setSqrtPrice(987 * Constants.Q96 / 1000);

        IFillerMarket.SettlementParams memory settlementData = _getSettlementData(Constants.Q96 * 9730 / 10000);

        vm.expectRevert(PerpMarket.TPSLConditionDoesNotMatch.selector);
        perpMarket.close(from2, 1, settlementData);
    }

    function testCloseFailsIfTPSLConditionNotMet() public {
        mockPriceFeed.setSqrtPrice(Constants.Q96);

        IFillerMarket.SettlementParams memory settlementData = _getSettlementData(Constants.Q96);

        vm.expectRevert(PerpMarket.TPSLConditionDoesNotMatch.selector);
        perpMarket.close(from1, 1, settlementData);
    }

    function testCloseSucceedsWithTP() public {
        IFillerMarket.SettlementParams memory settlementData = _getSettlementData(Constants.Q96 * 10220 / 10000);

        uint256 beforeBalance = currency1.balanceOf(from1);
        IPredyPool.TradeResult memory tradeResult = perpMarket.close(from1, 1, settlementData);
        uint256 afterBalance = currency1.balanceOf(from1);

        assertGe(uint256(tradeResult.averagePrice), 101 * Constants.Q96 / 100);

        // owner gets close value
        assertGt(afterBalance, beforeBalance);
    }

    function testCloseSucceedsWithSL() public {
        mockPriceFeed.setSqrtPrice(987 * Constants.Q96 / 1000);

        IFillerMarket.SettlementParams memory settlementData = _getSettlementData(Constants.Q96 * 9730 / 10000);

        uint256 beforeBalance = currency1.balanceOf(from1);
        perpMarket.close(from1, 1, settlementData);
        uint256 afterBalance = currency1.balanceOf(from1);

        // owner gets close value
        assertGt(afterBalance, beforeBalance);
    }
}
