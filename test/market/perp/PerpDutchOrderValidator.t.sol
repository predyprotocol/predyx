// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/markets/perp/PerpDutchOrderValidator.sol";

contract DutchOrderValidatorTest is Test {
    PerpDutchOrderValidator dutchOrderValidator;

    function setUp() public {
        dutchOrderValidator = new PerpDutchOrderValidator();
    }

    function testValidateEndTimeBeforeStartTime() public {
        PerpDutchOrderValidationData memory dutchOrderValidationData;

        dutchOrderValidationData.startPrice = 0;
        dutchOrderValidationData.endPrice = 0;
        dutchOrderValidationData.startTime = 100;
        dutchOrderValidationData.endTime = 99;

        PerpOrder memory gammaOrder;
        gammaOrder.tradeAmount = 1e6;
        gammaOrder.validationData = abi.encode(dutchOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        vm.expectRevert(DecayLib.EndTimeBeforeStartTime.selector);
        dutchOrderValidator.validate(gammaOrder, tradeResult);
    }

    function testValidateEndTimeAfterStartTime() public {
        PerpDutchOrderValidationData memory dutchOrderValidationData;

        dutchOrderValidationData.startPrice = 0;
        dutchOrderValidationData.endPrice = 0;
        dutchOrderValidationData.startTime = 100;
        dutchOrderValidationData.endTime = 101;

        PerpOrder memory gammaOrder;
        gammaOrder.tradeAmount = 1e6;
        gammaOrder.validationData = abi.encode(dutchOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        dutchOrderValidator.validate(gammaOrder, tradeResult);
    }

    function testValidatePriceGreaterThanLimit(int256 tradeAmount) public {
        vm.assume(-type(int128).max < tradeAmount && tradeAmount < type(int128).max);

        PerpDutchOrderValidationData memory dutchOrderValidationData;

        dutchOrderValidationData.startPrice = Constants.Q96 / 2;
        dutchOrderValidationData.endPrice = Constants.Q96;
        dutchOrderValidationData.startTime = block.timestamp;
        dutchOrderValidationData.endTime = block.timestamp + 100;

        PerpOrder memory gammaOrder;
        gammaOrder.tradeAmount = tradeAmount;
        gammaOrder.validationData = abi.encode(dutchOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        tradeResult.payoff.perpEntryUpdate = -tradeAmount;

        if (tradeAmount > 0) {
            vm.expectRevert(PerpDutchOrderValidator.PriceGreaterThanLimit.selector);
        }
        dutchOrderValidator.validate(gammaOrder, tradeResult);
    }

    function testValidatePriceLessThanLimit(int256 tradeAmount) public {
        vm.assume(-type(int128).max < tradeAmount && tradeAmount < type(int128).max);

        PerpDutchOrderValidationData memory dutchOrderValidationData;

        dutchOrderValidationData.startPrice = 2 * Constants.Q96;
        dutchOrderValidationData.endPrice = Constants.Q96;
        dutchOrderValidationData.startTime = block.timestamp;
        dutchOrderValidationData.endTime = block.timestamp + 100;

        PerpOrder memory gammaOrder;
        gammaOrder.tradeAmount = tradeAmount;
        gammaOrder.validationData = abi.encode(dutchOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        tradeResult.payoff.perpEntryUpdate = -tradeAmount;

        if (tradeAmount < 0) {
            vm.expectRevert(PerpDutchOrderValidator.PriceLessThanLimit.selector);
        }
        dutchOrderValidator.validate(gammaOrder, tradeResult);
    }
}
