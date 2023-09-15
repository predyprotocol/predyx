// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

library Math {
    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? b : a;
    }

    function mulDivDownInt256(int256 _x, uint256 _y, uint256 _z) internal pure returns (int256) {
        if (_x == 0) {
            return 0;
        } else if (_x > 0) {
            return int256(FullMath.mulDiv(uint256(_x), _y, _z));
        } else {
            return -int256(FullMath.mulDivRoundingUp(uint256(-_x), _y, _z));
        }
    }

    function addDelta(uint256 a, int256 b) internal pure returns (uint256) {
        if (b >= 0) {
            return a + uint256(b);
        } else {
            return a + uint256(-b);
        }
    }
}
