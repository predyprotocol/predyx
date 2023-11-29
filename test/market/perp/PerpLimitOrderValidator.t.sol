// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/markets/perp/PerpLimitOrderValidator.sol";

contract LimitOrderValidatorTest is Test {
    PerpLimitOrderValidator limitOrderValidator;

    function setUp() public {
        limitOrderValidator = new PerpLimitOrderValidator();
    }

    function testValidate(int256 tradeAmount) public {
        PerpLimitOrderValidationData memory limitOrderValidationData;

        PerpOrder memory gammaOrder;
        gammaOrder.tradeAmount = tradeAmount;
        gammaOrder.validationData = abi.encode(limitOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        limitOrderValidator.validate(gammaOrder, tradeResult);
    }

    function testValidatePriceGreaterThanLimit(int256 tradeAmount) public {
        vm.assume(-type(int128).max < tradeAmount && tradeAmount < type(int128).max);

        PerpLimitOrderValidationData memory limitOrderValidationData;

        limitOrderValidationData.limitPrice = Constants.Q96 / 2;

        PerpOrder memory gammaOrder;
        gammaOrder.tradeAmount = tradeAmount;
        gammaOrder.validationData = abi.encode(limitOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        tradeResult.payoff.perpEntryUpdate = -tradeAmount;

        if (tradeAmount > 0) {
            vm.expectRevert(PerpLimitOrderValidator.PriceGreaterThanLimit.selector);
        }
        limitOrderValidator.validate(gammaOrder, tradeResult);
    }

    function testValidatePriceLessThanLimit(int256 tradeAmount) public {
        vm.assume(-type(int128).max < tradeAmount && tradeAmount < type(int128).max);

        PerpLimitOrderValidationData memory limitOrderValidationData;

        limitOrderValidationData.limitPrice = 2 * Constants.Q96;

        PerpOrder memory gammaOrder;
        gammaOrder.tradeAmount = tradeAmount;
        gammaOrder.validationData = abi.encode(limitOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        tradeResult.payoff.perpEntryUpdate = -tradeAmount;

        if (tradeAmount < 0) {
            vm.expectRevert(PerpLimitOrderValidator.PriceLessThanLimit.selector);
        }
        limitOrderValidator.validate(gammaOrder, tradeResult);
    }
}
