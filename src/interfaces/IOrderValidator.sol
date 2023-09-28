// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "./IPredyPool.sol";
import "../libraries/market/GeneralOrderLib.sol";

interface IOrderValidator {
    function validate(GeneralOrder memory generalOrder, IPredyPool.TradeResult memory tradeResult) external pure;
}
