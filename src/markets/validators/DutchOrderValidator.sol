// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import "../../libraries/Constants.sol";
import "../../libraries/math/Math.sol";
import "../../libraries/orders/DecayLib.sol";

struct DutchOrderValidationData {
    uint256 startPrice;
    uint256 endPrice;
    uint256 startTime;
    uint256 endTime;
}

/**
 * @notice The DutchOrderValidator contract is responsible for validating the dutch auction orders
 */
contract DutchOrderValidator {
    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    error TriggerNotMatched();

    function validate(
        int256 tradeAmount,
        int256 tradeAmountSqrt,
        bytes memory validationData,
        IPredyPool.TradeResult memory tradeResult
    ) external view {
        require(tradeAmountSqrt == 0);

        DutchOrderValidationData memory validationParams = abi.decode(validationData, (DutchOrderValidationData));

        uint256 decayedPrice = DecayLib.decay(
            validationParams.startPrice, validationParams.endPrice, validationParams.startTime, validationParams.endTime
        );

        if (tradeAmount != 0) {
            uint256 tradePrice = Math.abs(tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff)
                * Constants.Q96 / Math.abs(tradeAmount);

            if (tradeAmount > 0 && decayedPrice < tradePrice) {
                revert PriceGreaterThanLimit();
            }

            if (tradeAmount < 0 && decayedPrice > tradePrice) {
                revert PriceLessThanLimit();
            }
        }
    }
}
