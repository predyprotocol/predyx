// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "./IPredyPool.sol";
import {GammaOrder, GammaOrderLib} from "../libraries/orders/GammaOrder.sol";
import {PerpOrder} from "../libraries/orders/PerpOrder.sol";

interface IOrderValidator {
    function validate(GammaOrder memory gammaOrder, IPredyPool.TradeResult memory tradeResult) external pure;
}

interface IPerpOrderValidator {
    function validate(PerpOrder memory perpOrder, IPredyPool.TradeResult memory tradeResult) external pure;
}
