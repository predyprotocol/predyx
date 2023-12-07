// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../interfaces/ILendingPool.sol";
import "./BaseSettlement.sol";

contract RevertSettlement is BaseSettlement {
    constructor(ILendingPool predyPool) BaseSettlement(predyPool) {}

    function predySettlementCallback(bytes memory, int256 baseAmountDelta) external view override(BaseSettlement) {
        if (address(_predyPool) != msg.sender) revert CallerIsNotLendingPool();

        _revertBaseAmountDelta(baseAmountDelta);
    }

    function quoteSettlement(bytes memory, int256) external pure override {
        _revertQuoteAmount(0);
    }

    function _revertBaseAmountDelta(int256 baseAmountDelta) internal pure {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, baseAmountDelta)
            revert(ptr, 32)
        }
    }
}
