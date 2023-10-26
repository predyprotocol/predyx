// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/libraries/orders/DutchOrderValidator.sol";

contract DutchOrderValidatorTest is Test {
    DutchOrderValidator dutchOrderValidator;

    function setUp() public {
        dutchOrderValidator = new DutchOrderValidator();
    }

    function testValidateEndTimeBeforeStartTime() public {
        DutchOrderValidationData memory dutchOrderValidationData;

        dutchOrderValidationData.startPrice = 0;
        dutchOrderValidationData.endPrice = 0;
        dutchOrderValidationData.startTime = 100;
        dutchOrderValidationData.endTime = 99;

        PerpOrder memory perpOrder;
        perpOrder.tradeAmount = 1e6;
        perpOrder.validationData = abi.encode(dutchOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        vm.expectRevert(DutchOrderValidator.EndTimeBeforeStartTime.selector);
        dutchOrderValidator.validate(perpOrder, tradeResult);
    }

    function testValidateEndTimeAfterStartTime() public {
        DutchOrderValidationData memory dutchOrderValidationData;

        dutchOrderValidationData.startPrice = 0;
        dutchOrderValidationData.endPrice = 0;
        dutchOrderValidationData.startTime = 100;
        dutchOrderValidationData.endTime = 101;

        PerpOrder memory perpOrder;
        perpOrder.tradeAmount = 1e6;
        perpOrder.validationData = abi.encode(dutchOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        dutchOrderValidator.validate(perpOrder, tradeResult);
    }

    function testValidatePriceGreaterThanLimit(int256 tradeAmount) public {
        vm.assume(-type(int128).max < tradeAmount && tradeAmount < type(int128).max);

        DutchOrderValidationData memory dutchOrderValidationData;

        dutchOrderValidationData.startPrice = Constants.Q96 / 2;
        dutchOrderValidationData.endPrice = Constants.Q96;
        dutchOrderValidationData.startTime = block.timestamp;
        dutchOrderValidationData.endTime = block.timestamp + 100;

        PerpOrder memory perpOrder;
        perpOrder.tradeAmount = tradeAmount;
        perpOrder.validationData = abi.encode(dutchOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        tradeResult.payoff.perpEntryUpdate = -tradeAmount;

        if (tradeAmount > 0) {
            vm.expectRevert(DutchOrderValidator.PriceGreaterThanLimit.selector);
        }
        dutchOrderValidator.validate(perpOrder, tradeResult);
    }

    function testValidatePriceLessThanLimit(int256 tradeAmount) public {
        vm.assume(-type(int128).max < tradeAmount && tradeAmount < type(int128).max);

        DutchOrderValidationData memory dutchOrderValidationData;

        dutchOrderValidationData.startPrice = 2 * Constants.Q96;
        dutchOrderValidationData.endPrice = Constants.Q96;
        dutchOrderValidationData.startTime = block.timestamp;
        dutchOrderValidationData.endTime = block.timestamp + 100;

        PerpOrder memory perpOrder;
        perpOrder.tradeAmount = tradeAmount;
        perpOrder.validationData = abi.encode(dutchOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        tradeResult.payoff.perpEntryUpdate = -tradeAmount;

        if (tradeAmount < 0) {
            vm.expectRevert(DutchOrderValidator.PriceLessThanLimit.selector);
        }
        dutchOrderValidator.validate(perpOrder, tradeResult);
    }
}
