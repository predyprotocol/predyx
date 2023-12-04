// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/markets/validators/LimitOrderValidator.sol";

contract LimitOrderValidatorTest is Test {
    LimitOrderValidator limitOrderValidator;

    function setUp() public {
        limitOrderValidator = new LimitOrderValidator();
    }

    function testValidate(int256 tradeAmount, int256 tradeAmountSqrt) public {
        LimitOrderValidationData memory limitOrderValidationData;

        bytes memory validationData = abi.encode(limitOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        limitOrderValidator.validate(tradeAmount, tradeAmountSqrt, validationData, tradeResult);
    }

    function testValidatePriceGreaterThanLimit(int256 tradeAmount) public {
        vm.assume(-type(int128).max < tradeAmount && tradeAmount < type(int128).max);

        LimitOrderValidationData memory limitOrderValidationData;

        limitOrderValidationData.limitPrice = Constants.Q96 / 2;

        bytes memory validationData = abi.encode(limitOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        tradeResult.payoff.perpEntryUpdate = -tradeAmount;

        if (tradeAmount > 0) {
            vm.expectRevert(LimitOrderValidator.PriceGreaterThanLimit.selector);
        }
        limitOrderValidator.validate(tradeAmount, 0, validationData, tradeResult);
    }

    function testValidatePriceLessThanLimit(int256 tradeAmount) public {
        vm.assume(-type(int128).max < tradeAmount && tradeAmount < type(int128).max);

        LimitOrderValidationData memory limitOrderValidationData;

        limitOrderValidationData.limitPrice = 2 * Constants.Q96;

        bytes memory validationData = abi.encode(limitOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        tradeResult.payoff.perpEntryUpdate = -tradeAmount;

        if (tradeAmount < 0) {
            vm.expectRevert(LimitOrderValidator.PriceLessThanLimit.selector);
        }
        limitOrderValidator.validate(tradeAmount, 0, validationData, tradeResult);
    }
}
