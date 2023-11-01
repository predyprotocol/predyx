// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import {BaseHookCallback} from "../../../src/base/BaseHookCallback.sol";

contract TestPerpExecLiquidationCall is TestPerpMarket {
    bytes normalSwapRoute;
    uint256 fromPrivateKey1;
    address from1;
    uint256 fromPrivateKey2;
    address from2;

    uint256 fillerPoolId;
    address _fillerAddress;

    function setUp() public override {
        TestPerpMarket.setUp();

        normalSwapRoute = abi.encodePacked(address(currency0), uint24(500), address(currency1));

        fillerPoolId = fillerMarket.addFillerPool(pairId);
        _fillerAddress = address(this);

        fillerMarket.depositToInsurancePool(1, 100 * 1e6);

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

        PerpOrder memory order = PerpOrder(
            OrderInfo(address(fillerMarket), from1, _fillerAddress, 0, block.timestamp + 100),
            0,
            1,
            address(currency1),
            -1000 * 1e4,
            210000,
            address(limitOrderValidator),
            abi.encode(PerpLimitOrderValidationData(0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        fillerMarket.executeOrder(
            signedOrder, settlement.getSettlementParams(normalSwapRoute, 0, address(currency1), address(currency0), 0)
        );
    }

    // liquidate succeeds if the vault is danger
    function testLiquidateSucceedsIfVaultIsDanger(uint256 closeRatio) public {}

    // liquidate succeeds and only filler can cover negative margin
    function testLiquidateSucceedsIfFillerCoverNegativeMargin() public {
        ISettlement.SettlementData memory settlementData =
            directSettlement.getSettlementParams(address(currency1), address(currency0), 12000);

        priceFeed.setSqrtPrice(12 * Constants.Q96 / 10);

        // vm.startPrank(from1);
        fillerMarket.execLiquidationCall(1, settlementData);
        // vm.stopPrank();

        (,,, int256 fillerMarginAmount,,,,,,) = fillerMarket.insurancePools(_fillerAddress, pairId);

        assertLt(fillerMarginAmount, int256(100 * 1e6));
    }

    // liquidate fails if slippage too large
    function testLiquidateFailIfSlippageTooLarge() public {
        //
    }

    // liquidate succeeds by premium payment
    function testLiquidateSucceedsByPremiumPayment() public {}

    // liquidate succeeds with insolvent vault
    function testLiquidateSucceedsWithInsolvent() public {}

    // liquidate fails if the vault is safe
    function testLiquidateFailsIfVaultIsSafe(uint256 sqrtPrice) public {
        vm.assume(sqrtPrice <= 100 * Constants.Q96);

        // 79247578957702974831301681716

        fillerMarket.depositToInsurancePool(1, 1e12);

        ISettlement.SettlementData memory settlementData = directSettlement.getSettlementParams(
            address(currency1), address(currency0), sqrtPrice * 1e4 / Constants.Q96
        );

        priceFeed.setSqrtPrice(sqrtPrice);
        if (sqrtPrice <= 100049009804 * Constants.Q96 / 1e11) {
            vm.expectRevert(PerpMarket.UserPositionIsNotDanger.selector);
        }
        fillerMarket.execLiquidationCall(1, settlementData);
    }

    // liquidate fails after liquidation
    function testLiquidateFailsAfterLiquidation() public {}
}
