// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

library PairLib {
    function getRebalanceCacheId(uint256 _pairId, uint64 _rebalanceId) internal pure returns (uint256) {
        return _pairId * type(uint64).max + _rebalanceId;
    }
}
