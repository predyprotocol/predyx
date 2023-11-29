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

    function _revertBaseAmountDelta(int256 baseAmountDelta) internal pure {
        bytes memory data = abi.encode(baseAmountDelta);

        assembly {
            revert(add(32, data), mload(data))
        }
    }
}
