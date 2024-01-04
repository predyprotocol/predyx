// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import {OrderInfo} from "../../../src/libraries/orders/OrderInfoLib.sol";
import {SpotDutchOrderValidator} from "../../../src/markets/spot/SpotDutchOrderValidator.sol";
import {SpotOrder} from "../../../src/markets/spot/SpotOrder.sol";

contract TestPerpExecuteOrder is TestSpotMarket {
    uint256 private fromPrivateKey1;
    address private from1;

    function setUp() public override {
        TestSpotMarket.setUp();

        fromPrivateKey1 = 0x12341234;
        from1 = vm.addr(fromPrivateKey1);

        currency0.mint(from1, type(uint128).max);
        currency1.mint(from1, type(uint128).max);

        vm.prank(from1);
        currency0.approve(address(permit2), type(uint256).max);

        vm.prank(from1);
        currency1.approve(address(permit2), type(uint256).max);

        currency0.mint(address(settlement), type(uint128).max);
        currency1.mint(address(settlement), type(uint128).max);
    }

    function _checkBalances() internal {
        assertEq(currency0.balanceOf(address(spotMarket)), 0);
        assertEq(currency1.balanceOf(address(spotMarket)), 0);
    }

    function invariantSpotMarket() external {
        _checkBalances();
    }

    function testExecuteOrderSucceedsForSwap() public {
        SpotOrder memory order = SpotOrder(
            OrderInfo(address(spotMarket), from1, 0, block.timestamp + 100),
            address(currency1),
            address(currency0),
            1000,
            1100,
            address(dutchOrderValidator),
            abi.encode(
                SpotDutchOrderValidationData(
                    Constants.Q96, Constants.Q96 + 1000, block.timestamp - 1 minutes, block.timestamp + 4 minutes
                )
            )
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        int256 quoteTokenAmount = spotMarket.executeOrder(signedOrder, _getSpotSettlementParams(1000, 1000));

        assertEq(quoteTokenAmount, -1000);

        _checkBalances();
    }

    function testExecuteOrderFailsIfExceedMax() public {
        SpotOrder memory order = SpotOrder(
            OrderInfo(address(spotMarket), from1, 0, block.timestamp + 100),
            address(currency1),
            address(currency0),
            1000,
            999,
            address(dutchOrderValidator),
            abi.encode(
                SpotDutchOrderValidationData(
                    Constants.Q96, Constants.Q96 + 1000000, block.timestamp - 1 minutes, block.timestamp + 4 minutes
                )
            )
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        SpotMarket.SettlementParams memory settlementData = _getSpotSettlementParams(1000, 1000);

        vm.expectRevert(bytes("TRANSFER_FAILED"));
        spotMarket.executeOrder(signedOrder, settlementData);
    }

    function testExecuteOrderFailsIfBaseCurrencyNotSettled() public {
        SpotOrder memory order = SpotOrder(
            OrderInfo(address(spotMarket), from1, 0, block.timestamp + 100),
            address(currency1),
            address(currency0),
            999,
            1000,
            address(dutchOrderValidator),
            abi.encode(
                SpotDutchOrderValidationData(
                    Constants.Q96, Constants.Q96 + 1000000, block.timestamp - 1 minutes, block.timestamp + 4 minutes
                )
            )
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);
        SpotMarket.SettlementParams memory settlementData = _getSpotSettlementParams(1000, 1000);

        vm.expectRevert(SpotMarket.BaseCurrencyNotSettled.selector);
        spotMarket.executeOrder(signedOrder, settlementData);
    }

    function testExecuteOrderFailsByValidation() public {
        SpotOrder memory order = SpotOrder(
            OrderInfo(address(spotMarket), from1, 0, block.timestamp + 100),
            address(currency1),
            address(currency0),
            1000,
            2000,
            address(dutchOrderValidator),
            abi.encode(
                SpotDutchOrderValidationData(
                    Constants.Q96, Constants.Q96 + 1000000, block.timestamp - 1 minutes, block.timestamp + 4 minutes
                )
            )
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);
        SpotMarket.SettlementParams memory settlementData = _getSpotSettlementParams(2000, 1000);

        vm.expectRevert(SpotDutchOrderValidator.PriceGreaterThanLimit.selector);
        spotMarket.executeOrder(signedOrder, settlementData);
    }

    function testExecuteOrderSucceedsForBuying() public {
        SpotOrder memory order = SpotOrder(
            OrderInfo(address(spotMarket), from1, 0, block.timestamp + 100),
            address(currency1),
            address(currency0),
            1000,
            1100,
            address(_spotExclusiveLimitOrderValidator),
            abi.encode(SpotExclusiveLimitOrderValidationData(address(this), 1012))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        uint256 snapshot = vm.snapshot();

        assertEq(spotMarket.executeOrder(signedOrder, _getUniSettlementData(1100, 0, 10)), -1012);

        _checkBalances();

        vm.revertTo(snapshot);

        assertEq(spotMarket.executeOrder(signedOrder, _getUniSettlementData(1100, Constants.Q96, 10)), -1000);

        _checkBalances();

        vm.revertTo(snapshot);

        assertEq(spotMarket.executeOrder(signedOrder, _getSettlementData(Constants.Q96)), -1000);
    }

    function testExecuteOrderSucceedsForSelling() public {
        SpotOrder memory order = SpotOrder(
            OrderInfo(address(spotMarket), from1, 0, block.timestamp + 100),
            address(currency1),
            address(currency0),
            -1000,
            1100,
            address(_spotExclusiveLimitOrderValidator),
            abi.encode(SpotExclusiveLimitOrderValidationData(address(this), 988))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        uint256 snapshot = vm.snapshot();

        assertEq(spotMarket.executeOrder(signedOrder, _getUniSettlementData(0, 0, 10)), 988);

        vm.revertTo(snapshot);

        assertEq(spotMarket.executeOrder(signedOrder, _getSettlementData(Constants.Q96)), 1000);
    }
}
