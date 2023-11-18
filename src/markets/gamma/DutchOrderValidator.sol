// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import "../../libraries/Constants.sol";
import "./GammaOrder.sol";
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

    function validate(GammaOrder memory gammaOrder, IPredyPool.TradeResult memory tradeResult) external view {
        require(gammaOrder.tradeAmountSqrt == 0);

        DutchOrderValidationData memory validationData =
            abi.decode(gammaOrder.validationData, (DutchOrderValidationData));

        uint256 decayedPrice = DecayLib.decay(
            validationData.startPrice, validationData.endPrice, validationData.startTime, validationData.endTime
        );

        if (gammaOrder.tradeAmount != 0) {
            uint256 tradePrice = Math.abs(tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff)
                * Constants.Q96 / Math.abs(gammaOrder.tradeAmount);

            if (gammaOrder.tradeAmount > 0 && decayedPrice < tradePrice) {
                revert PriceGreaterThanLimit();
            }

            if (gammaOrder.tradeAmount < 0 && decayedPrice > tradePrice) {
                revert PriceLessThanLimit();
            }
        }
    }
}
