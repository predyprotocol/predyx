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
    function quoteSettlement(bytes memory settlementData, int256 baseAmountDelta) external virtual;

    function _revertQuoteAmount(int256 quoteAmount) internal pure {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, quoteAmount)
            revert(ptr, 32)
        }
    }
}
