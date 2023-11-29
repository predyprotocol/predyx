// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Constants} from "../../libraries/Constants.sol";
import {Math} from "../../libraries/math/Math.sol";
import {SpotOrder} from "./SpotOrder.sol";

struct SpotExclusiveLimitOrderValidationData {
    address filler;
    uint256 limitPrice;
}

/**
 * @notice The LimitOrderValidator contract is responsible for validating the limit orders
 */
contract SpotExclusiveLimitOrderValidator {
    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    function validate(SpotOrder memory spotOrder, int256 baseTokenAmount, int256 quoteTokenAmount, address filler)
        external
        pure
    {
        SpotExclusiveLimitOrderValidationData memory validationData =
            abi.decode(spotOrder.validationData, (SpotExclusiveLimitOrderValidationData));

        require(validationData.filler == filler);

        if (spotOrder.baseTokenAmount != 0) {
            uint256 tradePrice = Math.abs(quoteTokenAmount) * Constants.Q96 / Math.abs(baseTokenAmount);

            if (spotOrder.baseTokenAmount > 0 && validationData.limitPrice < tradePrice) {
                revert PriceGreaterThanLimit();
            }

            if (spotOrder.baseTokenAmount < 0 && validationData.limitPrice > tradePrice) {
                revert PriceLessThanLimit();
            }
        }
    }
}
