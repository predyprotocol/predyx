// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import "../Constants.sol";
import "./PerpOrder.sol";
import "../math/Math.sol";

struct PerpLimitOrderValidationData {
    uint256 triggerPrice;
    uint256 limitPrice;
}

/**
 * @notice The LimitOrderValidator contract is responsible for validating the limit orders based on the trigger and limit prices.
 */
contract PerpLimitOrderValidator {
    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    error TriggerNotMatched();

    function validate(PerpOrder memory perpOrder, IPredyPool.TradeResult memory tradeResult) external pure {
        PerpLimitOrderValidationData memory validationData =
            abi.decode(perpOrder.validationData, (PerpLimitOrderValidationData));

        if (validationData.triggerPrice > 0) {
            uint256 twap = (tradeResult.sqrtTwap * tradeResult.sqrtTwap) >> Constants.RESOLUTION;

            if (perpOrder.tradeAmount > 0 && validationData.triggerPrice < twap) {
                revert TriggerNotMatched();
            }
            if (perpOrder.tradeAmount < 0 && validationData.triggerPrice > twap) {
                revert TriggerNotMatched();
            }
        }

        if (validationData.limitPrice > 0 && perpOrder.tradeAmount != 0) {
            uint256 tradePrice = Math.abs(tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff)
                * Constants.Q96 / Math.abs(perpOrder.tradeAmount);

            if (perpOrder.tradeAmount > 0 && validationData.limitPrice < tradePrice) {
                revert PriceGreaterThanLimit();
            }

            if (perpOrder.tradeAmount < 0 && validationData.limitPrice > tradePrice) {
                revert PriceLessThanLimit();
            }
        }
    }
}
