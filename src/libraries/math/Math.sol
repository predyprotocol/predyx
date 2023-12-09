// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";

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

    function fullMulDivInt256(int256 x, uint256 y, uint256 z) internal pure returns (int256) {
        if (x == 0) {
            return 0;
        } else if (x > 0) {
            return int256(FullMath.mulDiv(uint256(x), y, z));
        } else {
            return -int256(FullMath.mulDiv(uint256(-x), y, z));
        }
    }

    function fullMulDivDownInt256(int256 x, uint256 y, uint256 z) internal pure returns (int256) {
        if (x == 0) {
            return 0;
        } else if (x > 0) {
            return int256(FullMath.mulDiv(uint256(x), y, z));
        } else {
            return -int256(FullMath.mulDivRoundingUp(uint256(-x), y, z));
        }
    }

    function mulDivDownInt256(int256 x, uint256 y, uint256 z) internal pure returns (int256) {
        if (x == 0) {
            return 0;
        } else if (x > 0) {
            return int256(FixedPointMathLib.mulDivDown(uint256(x), y, z));
        } else {
            return -int256(FixedPointMathLib.mulDivUp(uint256(-x), y, z));
        }
    }

    function addDelta(uint256 a, int256 b) internal pure returns (uint256) {
        if (b >= 0) {
            return a + uint256(b);
        } else {
            return a - uint256(-b);
        }
    }
}
