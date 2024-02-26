// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Constants} from "../../libraries/Constants.sol";
import {Math} from "../../libraries/math/Math.sol";
import {DecayLib} from "../../libraries/orders/DecayLib.sol";
import {SpotOrder} from "./SpotOrder.sol";

struct SpotDutchOrderValidationData {
    uint256 startAmount;
    uint256 endAmount;
    uint256 startTime;
    uint256 endTime;
}

/**
 * @notice The DutchOrderValidator contract is responsible for validating the dutch auction orders
 */
contract SpotDutchOrderValidator {
    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    function validate(SpotOrder memory spotOrder, int256 quoteTokenAmount, address) external view {
        SpotDutchOrderValidationData memory validationData =
            abi.decode(spotOrder.validationData, (SpotDutchOrderValidationData));

        uint256 decayedAmount = DecayLib.decay(
            validationData.startAmount, validationData.endAmount, validationData.startTime, validationData.endTime
        );

        if (spotOrder.baseTokenAmount != 0) {
            uint256 quoteTokenAmountAbs = Math.abs(quoteTokenAmount);

            if (spotOrder.baseTokenAmount > 0 && decayedAmount < quoteTokenAmountAbs) {
                revert PriceGreaterThanLimit();
            }

            if (spotOrder.baseTokenAmount < 0 && decayedAmount > quoteTokenAmountAbs) {
                revert PriceLessThanLimit();
            }
        }
    }
}
