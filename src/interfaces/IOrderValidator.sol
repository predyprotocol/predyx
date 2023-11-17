// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "./IPredyPool.sol";
import {GammaOrder, GammaOrderLib} from "../markets/gamma/GammaOrder.sol";
import {PredictOrder} from "../markets/predict/PredictOrder.sol";

interface IOrderValidator {
    function validate(GammaOrder memory gammaOrder, IPredyPool.TradeResult memory tradeResult) external pure;
}

interface IPredictOrderValidator {
    function validate(PredictOrder memory predictOrder, IPredyPool.TradeResult memory tradeResult) external pure;
}
