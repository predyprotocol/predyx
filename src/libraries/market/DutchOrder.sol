// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import "../Constants.sol";
import "./GeneralOrderLib.sol";
import "../math/Math.sol";

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
    error EndTimeBeforeStartTime();

    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    error TriggerNotMatched();

    function validate(GeneralOrder memory generalOrder, IPredyPool.TradeResult memory tradeResult) external view {
        DutchOrderValidationData memory validationData =
            abi.decode(generalOrder.validationData, (DutchOrderValidationData));

        require(generalOrder.tradeAmountSqrt == 0);

        uint256 decayedPrice =
            decay(validationData.startPrice, validationData.endPrice, validationData.startTime, validationData.endTime);

        if (generalOrder.tradeAmount != 0) {
            uint256 tradePrice = Math.abs(tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff)
                * Constants.Q96 / Math.abs(generalOrder.tradeAmount);

            if (generalOrder.tradeAmount > 0 && decayedPrice < tradePrice) {
                revert PriceGreaterThanLimit();
            }

            if (generalOrder.tradeAmount < 0 && decayedPrice > tradePrice) {
                revert PriceLessThanLimit();
            }
        }
    }

    function decay(uint256 startPrice, uint256 endPrice, uint256 decayStartTime, uint256 decayEndTime)
        internal
        view
        returns (uint256 decayedPrice)
    {
        if (decayEndTime < decayStartTime) {
            revert EndTimeBeforeStartTime();
        } else if (decayEndTime <= block.timestamp) {
            decayedPrice = endPrice;
        } else if (decayStartTime >= block.timestamp) {
            decayedPrice = startPrice;
        } else {
            uint256 elapsed = block.timestamp - decayStartTime;
            uint256 duration = decayEndTime - decayStartTime;

            if (endPrice < startPrice) {
                decayedPrice = startPrice - (startPrice - endPrice) * elapsed / duration;
            } else {
                decayedPrice = startPrice + (endPrice - startPrice) * elapsed / duration;
            }
        }
    }
}
