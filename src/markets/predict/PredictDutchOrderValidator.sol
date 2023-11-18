// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import "../../libraries/Constants.sol";
import "./PredictOrder.sol";
import "../../libraries/math/Math.sol";
import "../../libraries/orders/DecayLib.sol";

struct PredictDutchOrderValidationData {
    uint256 startPrice;
    uint256 endPrice;
    uint256 startTime;
    uint256 endTime;
}

/**
 * @notice The DutchOrderValidator contract is responsible for validating the dutch auction orders
 */
contract PredictDutchOrderValidator {
    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    error TriggerNotMatched();

    function validate(PredictOrder memory predictOrder, IPredyPool.TradeResult memory tradeResult) external view {
        PredictDutchOrderValidationData memory validationData =
            abi.decode(predictOrder.validationData, (PredictDutchOrderValidationData));

        uint256 decayedPrice = DecayLib.decay(
            validationData.startPrice, validationData.endPrice, validationData.startTime, validationData.endTime
        );

        if (tradeResult.averagePrice < 0 && decayedPrice < uint256(-tradeResult.averagePrice)) {
            revert PriceGreaterThanLimit();
        }

        if (tradeResult.averagePrice > 0 && decayedPrice > uint256(tradeResult.averagePrice)) {
            revert PriceLessThanLimit();
        }
    }
}
