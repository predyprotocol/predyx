// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../interfaces/IPredyPool.sol";
import "../interfaces/IHooks.sol";

abstract contract BaseHookCallback is IHooks {
    IPredyPool predyPool;

    constructor(IPredyPool _predyPool) {
        predyPool = _predyPool;
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
