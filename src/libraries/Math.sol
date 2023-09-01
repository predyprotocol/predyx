// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

library Math {
    function addDelta(uint256 a, int256 b) internal pure returns (uint256) {
        if (b >= 0) {
            return a + uint256(b);
        } else {
            return a + uint256(-b);
        }
    }
}
