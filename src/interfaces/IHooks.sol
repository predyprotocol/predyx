// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./IPredyPool.sol";

interface IHooks {
    function predySettlementCallback(
        bytes memory settlementData,
        int256 quoteAmountDelta,
        int256 baseAmountDelta
    ) external;
    function predyTradeAfterCallback(IPredyPool.TradeParams memory tradeParams, IPredyPool.TradeResult memory tradeResult) external;
    function predyLiquidationCallback(IPredyPool.TradeParams memory tradeParams, IPredyPool.TradeResult memory tradeResult) external;
}
