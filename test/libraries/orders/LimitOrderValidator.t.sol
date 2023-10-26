// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/libraries/orders/LimitOrderValidator.sol";

contract LimitOrderValidatorTest is Test {
    LimitOrderValidator limitOrderValidator;

    function setUp() public {
        limitOrderValidator = new LimitOrderValidator();
    }

    function testValidate(int256 tradeAmount, int256 tradeAmountSqrt) public {
        LimitOrderValidationData memory limitOrderValidationData;

        GammaOrder memory gammaOrder;
        gammaOrder.tradeAmount = tradeAmount;
        gammaOrder.tradeAmountSqrt = tradeAmountSqrt;
        gammaOrder.validationData = abi.encode(limitOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        limitOrderValidator.validate(gammaOrder, tradeResult);
    }

    function testValidatePriceGreaterThanLimit(int256 tradeAmount) public {
        vm.assume(-type(int128).max < tradeAmount && tradeAmount < type(int128).max);

        LimitOrderValidationData memory limitOrderValidationData;

        limitOrderValidationData.limitPrice = Constants.Q96 / 2;

        GammaOrder memory gammaOrder;
        gammaOrder.tradeAmount = tradeAmount;
        gammaOrder.validationData = abi.encode(limitOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        tradeResult.payoff.perpEntryUpdate = -tradeAmount;

        if (tradeAmount > 0) {
            vm.expectRevert(LimitOrderValidator.PriceGreaterThanLimit.selector);
        }
        limitOrderValidator.validate(gammaOrder, tradeResult);
    }

    function testValidatePriceLessThanLimit(int256 tradeAmount) public {
        vm.assume(-type(int128).max < tradeAmount && tradeAmount < type(int128).max);

        LimitOrderValidationData memory limitOrderValidationData;

        limitOrderValidationData.limitPrice = 2 * Constants.Q96;

        GammaOrder memory gammaOrder;
        gammaOrder.tradeAmount = tradeAmount;
        gammaOrder.validationData = abi.encode(limitOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        tradeResult.payoff.perpEntryUpdate = -tradeAmount;

        if (tradeAmount < 0) {
            vm.expectRevert(LimitOrderValidator.PriceLessThanLimit.selector);
        }
        limitOrderValidator.validate(gammaOrder, tradeResult);
    }
}
