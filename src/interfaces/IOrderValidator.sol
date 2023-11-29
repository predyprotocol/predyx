// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "./IPredyPool.sol";
import {PerpOrder} from "../markets/perp/PerpOrder.sol";
import {GammaOrder} from "../markets/gamma/GammaOrder.sol";
import {PredictOrder} from "../markets/predict/PredictOrder.sol";
import {SpotOrder} from "../markets/spot/SpotOrder.sol";

interface IOrderValidator {
    function validate(PerpOrder memory perpOrder, IPredyPool.TradeResult memory tradeResult) external pure;
}

interface IGammaOrderValidator {
    function validate(GammaOrder memory gammaOrder, IPredyPool.TradeResult memory tradeResult) external pure;
}

interface IPredictOrderValidator {
    function validate(PredictOrder memory predictOrder, IPredyPool.TradeResult memory tradeResult) external pure;
}

interface ISpotOrderValidator {
    function validate(SpotOrder memory spotOrder, int256 baseTokenAmount, int256 quoteTokenAmount, address filler)
        external
        pure;
}
