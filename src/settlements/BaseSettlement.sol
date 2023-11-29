// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "../interfaces/ILendingPool.sol";
import "../interfaces/ISettlement.sol";

abstract contract BaseSettlement is ISettlement {
    ILendingPool immutable _predyPool;

    error CallerIsNotLendingPool();

    constructor(ILendingPool predyPool) {
        _predyPool = predyPool;
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta) external virtual;
}
