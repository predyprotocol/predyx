// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-core/contracts/libraries/UnsafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

library LPMath {
    function calculateAmount0ForLiquidityWithTicks(
        int24 _tickA,
        int24 _tickB,
        uint256 _liquidityAmount,
        bool _isRoundUp
    ) internal pure returns (int256) {
        return calculateAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(_tickA), TickMath.getSqrtRatioAtTick(_tickB), _liquidityAmount, _isRoundUp
        );
    }

    function calculateAmount1ForLiquidityWithTicks(
        int24 _tickA,
        int24 _tickB,
        uint256 _liquidityAmount,
        bool _isRoundUp
    ) internal pure returns (int256) {
        return calculateAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(_tickA), TickMath.getSqrtRatioAtTick(_tickB), _liquidityAmount, _isRoundUp
        );
    }

    function calculateAmount0ForLiquidity(
        uint160 _sqrtRatioA,
        uint160 _sqrtRatioB,
        uint256 _liquidityAmount,
        bool _isRoundUp
    ) internal pure returns (int256) {
        if (_liquidityAmount == 0 || _sqrtRatioA == _sqrtRatioB) {
            return 0;
        }

        bool swaped = _sqrtRatioA > _sqrtRatioB;

        if (_sqrtRatioA > _sqrtRatioB) (_sqrtRatioA, _sqrtRatioB) = (_sqrtRatioB, _sqrtRatioA);

        int256 r;

        bool isRoundUp = swaped ? !_isRoundUp : _isRoundUp;
        uint256 numerator = _liquidityAmount;

        if (isRoundUp) {
            uint256 r0 = FullMath.mulDivRoundingUp(numerator, FixedPoint96.Q96, _sqrtRatioA);
            uint256 r1 = FullMath.mulDiv(numerator, FixedPoint96.Q96, _sqrtRatioB);

            r = SafeCast.toInt256(r0) - SafeCast.toInt256(r1);
        } else {
            uint256 r0 = FullMath.mulDiv(numerator, FixedPoint96.Q96, _sqrtRatioA);
            uint256 r1 = FullMath.mulDivRoundingUp(numerator, FixedPoint96.Q96, _sqrtRatioB);

            r = SafeCast.toInt256(r0) - SafeCast.toInt256(r1);
        }

        if (swaped) {
            return -r;
        } else {
            return r;
        }
    }

    function calculateAmount1ForLiquidity(
        uint160 _sqrtRatioA,
        uint160 _sqrtRatioB,
        uint256 _liquidityAmount,
        bool _isRoundUp
    ) internal pure returns (int256) {
        if (_liquidityAmount == 0 || _sqrtRatioA == _sqrtRatioB) {
            return 0;
        }

        bool swaped = _sqrtRatioA < _sqrtRatioB;

        if (_sqrtRatioA < _sqrtRatioB) (_sqrtRatioA, _sqrtRatioB) = (_sqrtRatioB, _sqrtRatioA);

        int256 r;

        bool isRoundUp = swaped ? !_isRoundUp : _isRoundUp;

        if (isRoundUp) {
            uint256 r0 = FullMath.mulDivRoundingUp(_liquidityAmount, _sqrtRatioA, FixedPoint96.Q96);
            uint256 r1 = FullMath.mulDiv(_liquidityAmount, _sqrtRatioB, FixedPoint96.Q96);

            r = SafeCast.toInt256(r0) - SafeCast.toInt256(r1);
        } else {
            uint256 r0 = FullMath.mulDiv(_liquidityAmount, _sqrtRatioA, FixedPoint96.Q96);
            uint256 r1 = FullMath.mulDivRoundingUp(_liquidityAmount, _sqrtRatioB, FixedPoint96.Q96);

            r = SafeCast.toInt256(r0) - SafeCast.toInt256(r1);
        }

        if (swaped) {
            return -r;
        } else {
            return r;
        }
    }

    /**
     * @notice Calculates L / (1.0001)^(b/2)
     */
    function calculateAmount0OffsetWithTick(int24 _upper, uint256 _liquidityAmount, bool _isRoundUp)
        internal
        pure
        returns (int256)
    {
        return
            SafeCast.toInt256(calculateAmount0Offset(TickMath.getSqrtRatioAtTick(_upper), _liquidityAmount, _isRoundUp));
    }

    /**
     * @notice Calculates L / sqrt{p_b}
     */
    function calculateAmount0Offset(uint160 _sqrtRatio, uint256 _liquidityAmount, bool _isRoundUp)
        internal
        pure
        returns (uint256)
    {
        if (_isRoundUp) {
            return FullMath.mulDivRoundingUp(_liquidityAmount, FixedPoint96.Q96, _sqrtRatio);
        } else {
            return FullMath.mulDiv(_liquidityAmount, FixedPoint96.Q96, _sqrtRatio);
        }
    }

    /**
     * @notice Calculates L * (1.0001)^(a/2)
     */
    function calculateAmount1OffsetWithTick(int24 _lower, uint256 _liquidityAmount, bool _isRoundUp)
        internal
        pure
        returns (int256)
    {
        return
            SafeCast.toInt256(calculateAmount1Offset(TickMath.getSqrtRatioAtTick(_lower), _liquidityAmount, _isRoundUp));
    }

    /**
     * @notice Calculates L * sqrt{p_a}
     */
    function calculateAmount1Offset(uint160 _sqrtRatio, uint256 _liquidityAmount, bool _isRoundUp)
        internal
        pure
        returns (uint256)
    {
        if (_isRoundUp) {
            return FullMath.mulDivRoundingUp(_liquidityAmount, _sqrtRatio, FixedPoint96.Q96);
        } else {
            return FullMath.mulDiv(_liquidityAmount, _sqrtRatio, FixedPoint96.Q96);
        }
    }
}
