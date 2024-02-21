// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {
    SpotLimitOrderValidator,
    SpotLimitOrderValidationData,
    SpotOrder
} from "../../../src/markets/spot/SpotLimitOrderValidator.sol";
import {OrderInfo} from "../../../src/libraries/orders/OrderInfoLib.sol";

contract SpotLimitOrderValidatorTest is Test {
    SpotLimitOrderValidator internal spotLimitOrderValidator;

    bytes internal validationData;

    function setUp() public {
        spotLimitOrderValidator = new SpotLimitOrderValidator();

        SpotLimitOrderValidationData memory spotLimitOrderValidationData;

        spotLimitOrderValidationData.limitQuoteTokenAmount = 1000;

        validationData = abi.encode(spotLimitOrderValidationData);
    }

    function testValidateSpotLimitOrderBuy() public {
        SpotOrder memory order = SpotOrder(
            OrderInfo(address(1), address(2), 0, 10), address(3), address(4), 1000, 1000, address(5), validationData
        );

        spotLimitOrderValidator.validate(order, -800, address(0));

        vm.expectRevert(SpotLimitOrderValidator.PriceGreaterThanLimit.selector);
        spotLimitOrderValidator.validate(order, -1200, address(0));
    }

    function testValidateSpotLimitOrderSell() public {
        SpotOrder memory order = SpotOrder(
            OrderInfo(address(1), address(2), 0, 10), address(3), address(4), -1000, 1000, address(5), validationData
        );

        spotLimitOrderValidator.validate(order, 1200, address(0));

        vm.expectRevert(SpotLimitOrderValidator.PriceLessThanLimit.selector);
        spotLimitOrderValidator.validate(order, 800, address(0));
    }
}
