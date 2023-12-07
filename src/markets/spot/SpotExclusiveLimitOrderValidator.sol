// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Constants} from "../../libraries/Constants.sol";
import {Math} from "../../libraries/math/Math.sol";
import {SpotOrder} from "./SpotOrder.sol";

struct SpotExclusiveLimitOrderValidationData {
    address filler;
    uint256 limitQuoteTokenAmount;
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
            if (spotOrder.baseTokenAmount > 0 && validationData.limitQuoteTokenAmount < uint256(-quoteTokenAmount)) {
                revert PriceGreaterThanLimit();
            }

            if (spotOrder.baseTokenAmount < 0 && validationData.limitQuoteTokenAmount > uint256(quoteTokenAmount)) {
                revert PriceLessThanLimit();
            }
        }
    }
}
