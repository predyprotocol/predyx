// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/libraries/math/Math.sol";

contract MathTest is Test {
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;

    function testAbs(uint256 _x) public {
        uint256 expected = bound(_x, 0, uint256(type(int256).max));

        int256 p = int256(expected);
        int256 n = -int256(expected);

        assertEq(Math.abs(p), expected);
        assertEq(Math.abs(n), expected);
    }

    function testMin(uint256 _x) public {
        assertLe(Math.min(100, _x), 100);
    }

    function testMax(uint256 _x) public {
        assertGe(Math.max(100, _x), 100);
    }

    function testMulDivDownInt256() public {
        assertEq(Math.mulDivDownInt256(111, 111, 2), 6160);
        assertEq(Math.mulDivDownInt256(-111, 111, 2), -6161);
    }

    function testMulDivDownInt256Fuzz(uint256 _x) public {
        assertGe(Math.mulDivDownInt256(111, _x, Q128), 0);
        assertLe(Math.mulDivDownInt256(-111, _x, Q128), 0);
    }
}
