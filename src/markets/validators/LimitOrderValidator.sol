// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import "../../libraries/Constants.sol";
import "../../libraries/math/Math.sol";

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

    function validate(
        int256 tradeAmount,
        int256 tradeAmountSqrt,
        bytes memory validationData,
        IPredyPool.TradeResult memory tradeResult
    ) external view {
        LimitOrderValidationData memory validationParams = abi.decode(validationData, (LimitOrderValidationData));

        if (validationParams.triggerPrice > 0) {
            uint256 twap = (tradeResult.sqrtTwap * tradeResult.sqrtTwap) >> Constants.RESOLUTION;

            if (tradeAmount > 0 && validationParams.triggerPrice < twap) {
                revert TriggerNotMatched();
            }
            if (tradeAmount < 0 && validationParams.triggerPrice > twap) {
                revert TriggerNotMatched();
            }
        }

        if (validationParams.triggerPriceSqrt > 0) {
            if (tradeAmountSqrt > 0 && validationParams.triggerPriceSqrt < tradeResult.sqrtTwap) {
                revert TriggerNotMatched();
            }
            if (tradeAmountSqrt < 0 && validationParams.triggerPriceSqrt > tradeResult.sqrtTwap) {
                revert TriggerNotMatched();
            }
        }

        if (validationParams.limitPrice > 0 && tradeAmount != 0) {
            uint256 tradePrice = Math.abs(tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff)
                * Constants.Q96 / Math.abs(tradeAmount);

            if (tradeAmount > 0 && validationParams.limitPrice < tradePrice) {
                revert PriceGreaterThanLimit();
            }

            if (tradeAmount < 0 && validationParams.limitPrice > tradePrice) {
                revert PriceLessThanLimit();
            }
        }

        if (validationParams.limitPriceSqrt > 0 && tradeAmountSqrt != 0) {
            uint256 tradePriceSqrt = Math.abs(tradeResult.payoff.sqrtEntryUpdate + tradeResult.payoff.sqrtPayoff)
                * Constants.Q96 / Math.abs(tradeAmountSqrt);

            if (tradeAmountSqrt > 0 && validationParams.limitPriceSqrt < tradePriceSqrt) {
                revert PriceGreaterThanLimit();
            }

            if (tradeAmountSqrt < 0 && validationParams.limitPriceSqrt > tradePriceSqrt) {
                revert PriceLessThanLimit();
            }
        }
    }
}
