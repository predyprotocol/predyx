// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import {IPredyPool} from "./IPredyPool.sol";
import {SpotOrder} from "../markets/spot/SpotOrder.sol";

interface IOrderValidator {
    function validate(
        int256 tradeAmount,
        int256 tradeAmountSqrt,
        bytes memory validationData,
        IPredyPool.TradeResult memory tradeResult
    ) external pure;
}

interface ISpotOrderValidator {
    function validate(SpotOrder memory spotOrder, int256 baseTokenAmount, int256 quoteTokenAmount, address filler)
        external
        pure;
}
