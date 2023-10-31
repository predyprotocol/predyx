// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../interfaces/ILendingPool.sol";
import "../interfaces/ISettlement.sol";

abstract contract BaseSettlement is ISettlement {
    ILendingPool _predyPool;

    constructor(ILendingPool predyPool) {
        _predyPool = predyPool;
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta) external virtual;
}
