// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../interfaces/IPredyPool.sol";
import "../interfaces/ISettlement.sol";

abstract contract BaseSettlement is ISettlement {
    IPredyPool _predyPool;

    constructor(IPredyPool predyPool) {
        _predyPool = predyPool;
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta) external virtual;
}
