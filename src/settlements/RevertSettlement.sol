// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../interfaces/IPredyPool.sol";
import "./BaseSettlement.sol";

contract RevertSettlement is BaseSettlement {
    constructor(IPredyPool _predyPool) BaseSettlement(_predyPool) {}

    function predySettlementCallback(bytes memory, int256 baseAmountDelta) external override(BaseSettlement) {
        _revertBaseAmountDelta(baseAmountDelta);
    }

    function _revertBaseAmountDelta(int256 baseAmountDelta) internal pure {
        bytes memory data = abi.encode(baseAmountDelta);

        assembly {
            revert(add(32, data), mload(data))
        }
    }
}
