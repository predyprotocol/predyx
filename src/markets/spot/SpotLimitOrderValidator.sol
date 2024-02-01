// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SpotOrder} from "./SpotOrder.sol";

struct SpotLimitOrderValidationData {
    uint256 limitQuoteTokenAmount;
}

/**
 * @notice The LimitOrderValidator contract is responsible for validating the limit orders
 */
contract SpotLimitOrderValidator {
    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    function validate(SpotOrder memory spotOrder, int256 quoteTokenAmount, address) external pure {
        SpotLimitOrderValidationData memory validationData =
            abi.decode(spotOrder.validationData, (SpotLimitOrderValidationData));

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
