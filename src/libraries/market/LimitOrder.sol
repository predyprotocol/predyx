// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import "../Constants.sol";
import "./GeneralOrderLib.sol";
import "../math/Math.sol";

struct LimitOrderValidationData {
    uint256 triggerPrice;
    uint256 triggerPriceSqrt;
    uint256 limitPrice;
    uint256 limitPriceSqrt;
}

/**
 * @notice The LimitOrderValidator contract is responsible for validating the limit orders based on the trigger and limit prices.
 */
contract LimitOrderValidator {
    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    error TriggerNotMatched();

    function validate(GeneralOrder memory generalOrder, IPredyPool.TradeResult memory tradeResult) external pure {
        LimitOrderValidationData memory validationData =
            abi.decode(generalOrder.validationData, (LimitOrderValidationData));

        if (validationData.triggerPrice > 0) {
            uint256 twap = (tradeResult.sqrtTwap * tradeResult.sqrtTwap) >> Constants.RESOLUTION;

            if (generalOrder.tradeAmount > 0 && validationData.triggerPrice < twap) {
                revert TriggerNotMatched();
            }
            if (generalOrder.tradeAmount < 0 && validationData.triggerPrice > twap) {
                revert TriggerNotMatched();
            }
        }

        if (validationData.triggerPriceSqrt > 0) {
            if (generalOrder.tradeAmountSqrt > 0 && validationData.triggerPriceSqrt < tradeResult.sqrtTwap) {
                revert TriggerNotMatched();
            }
            if (generalOrder.tradeAmountSqrt < 0 && validationData.triggerPriceSqrt > tradeResult.sqrtTwap) {
                revert TriggerNotMatched();
            }
        }

        if (validationData.limitPrice > 0 && generalOrder.tradeAmount != 0) {
            uint256 tradePrice = Math.abs(tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff)
                * Constants.Q96 / Math.abs(generalOrder.tradeAmount);

            if (generalOrder.tradeAmount > 0 && validationData.limitPrice < tradePrice) {
                revert PriceGreaterThanLimit();
            }

            if (generalOrder.tradeAmount < 0 && validationData.limitPrice > tradePrice) {
                revert PriceLessThanLimit();
            }
        }

        if (validationData.limitPriceSqrt > 0 && generalOrder.tradeAmountSqrt != 0) {
            uint256 tradePriceSqrt = Math.abs(tradeResult.payoff.sqrtEntryUpdate + tradeResult.payoff.sqrtPayoff)
                * Constants.Q96 / Math.abs(generalOrder.tradeAmountSqrt);

            if (generalOrder.tradeAmountSqrt > 0 && validationData.limitPriceSqrt < tradePriceSqrt) {
                revert PriceGreaterThanLimit();
            }

            if (generalOrder.tradeAmountSqrt < 0 && validationData.limitPriceSqrt > tradePriceSqrt) {
                revert PriceLessThanLimit();
            }
        }
    }
}
