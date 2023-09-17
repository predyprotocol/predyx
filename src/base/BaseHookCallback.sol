// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../interfaces/IPredyPool.sol";
import "../interfaces/IHooks.sol";

abstract contract BaseHookCallback is IHooks {
    IPredyPool _predyPool;

    constructor(IPredyPool predyPool) {
        _predyPool = predyPool;
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta) external virtual;

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external virtual;

    function predyLiquidationCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external virtual;
}
