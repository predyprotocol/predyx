// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";

contract TestLevExecuteOrder is TestLevMarket {
    bytes normalSwapRoute;
    uint256 fromPrivateKey1;
    address from1;
    uint256 fromPrivateKey2;
    address from2;
    address _fillerAddress;

    function setUp() public override {
        TestLevMarket.setUp();

        _fillerAddress = market.addFillerPool(1);

        predyPool.supply(1, true, 1e10);
        predyPool.supply(1, false, 1e10);

        normalSwapRoute = abi.encodePacked(address(currency0), uint24(500), address(currency1));

        market.depositToInsurancePool(1, 100 * 1e6);

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

    function testConfirmLiquidation() public {
        GammaOrder memory order = GammaOrder(
            OrderInfo(address(market), from1, 0, block.timestamp + 100),
            0,
            1,
            address(currency1),
            -100 * 1e6,
            0,
            2 * 1e6,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        market.executeOrder(
            _fillerAddress,
            signedOrder,
            settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0)
        );

        priceFeed.setSqrtPrice(12 * Constants.Q96 / 10);

        predyPool.execLiquidationCall(
            1, 1e18, directSettlement.getSettlementParams(address(currency1), address(currency0), 12000)
        );

        market.confirmLiquidation(
            1, directSettlement.getSettlementParams(address(currency1), address(currency0), 12000)
        );

        (,,,,,,, int256 marginAmount,) = market.userPositions(1);

        assertEq(marginAmount, 0);
    }
}
