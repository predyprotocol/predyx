// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import "../../libraries/Constants.sol";
import "./PerpOrder.sol";
import "../../libraries/math/Math.sol";
import "../../libraries/orders/DecayLib.sol";

struct PerpDutchOrderValidationData {
    uint256 startPrice;
    uint256 endPrice;
    uint256 startTime;
    uint256 endTime;
}

/**
 * @notice The DutchOrderValidator contract is responsible for validating the dutch auction orders
 */
contract PerpDutchOrderValidator {
    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    error TriggerNotMatched();

    function validate(PerpOrder memory perpOrder, IPredyPool.TradeResult memory tradeResult) external view {
        PerpDutchOrderValidationData memory validationData =
            abi.decode(perpOrder.validationData, (PerpDutchOrderValidationData));

        uint256 decayedPrice = DecayLib.decay(
            validationData.startPrice, validationData.endPrice, validationData.startTime, validationData.endTime
        );

        if (perpOrder.tradeAmount != 0) {
            uint256 tradePrice = Math.abs(tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff)
                * Constants.Q96 / Math.abs(perpOrder.tradeAmount);

            if (perpOrder.tradeAmount > 0 && decayedPrice < tradePrice) {
                revert PriceGreaterThanLimit();
            }

            if (perpOrder.tradeAmount < 0 && decayedPrice > tradePrice) {
                revert PriceLessThanLimit();
            }
        }
    }
}
