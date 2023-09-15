// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./Perp.sol";
import "./ScaledAsset.sol";

library Reallocation {
    using SafeCast for uint256;

    /**
     * @notice Gets new available range
     */
    function getNewRange(Perp.PairStatus memory _assetStatusUnderlying, int24 _currentTick)
        internal
        view
        returns (int24 lower, int24 upper)
    {
        int24 tickSpacing = IUniswapV3Pool(_assetStatusUnderlying.sqrtAssetStatus.uniswapPool).tickSpacing();

        ScaledAsset.AssetStatus memory token0Status;
        ScaledAsset.AssetStatus memory token1Status;

        if (_assetStatusUnderlying.isMarginZero) {
            token0Status = _assetStatusUnderlying.quotePool.tokenStatus;
            token1Status = _assetStatusUnderlying.basePool.tokenStatus;
        } else {
            token0Status = _assetStatusUnderlying.basePool.tokenStatus;
            token1Status = _assetStatusUnderlying.quotePool.tokenStatus;
        }

        return _getNewRange(_assetStatusUnderlying, token0Status, token1Status, _currentTick, tickSpacing);
    }

    function _getNewRange(
        Perp.PairStatus memory _assetStatusUnderlying,
        ScaledAsset.AssetStatus memory _token0Status,
        ScaledAsset.AssetStatus memory _token1Status,
        int24 _currentTick,
        int24 _tickSpacing
    ) internal pure returns (int24 lower, int24 upper) {
        Perp.SqrtPerpAssetStatus memory sqrtAssetStatus = _assetStatusUnderlying.sqrtAssetStatus;

        lower = _currentTick - _assetStatusUnderlying.riskParams.rangeSize;
        upper = _currentTick + _assetStatusUnderlying.riskParams.rangeSize;

        int24 previousCenterTick = (sqrtAssetStatus.tickLower + sqrtAssetStatus.tickUpper) / 2;

        uint256 availableAmount = sqrtAssetStatus.totalAmount - sqrtAssetStatus.borrowedAmount;

        if (availableAmount > 0) {
            if (_currentTick < previousCenterTick) {
                // move to lower
                int24 minLowerTick = calculateMinLowerTick(
                    sqrtAssetStatus.tickLower,
                    ScaledAsset.getAvailableCollateralValue(_token1Status),
                    availableAmount,
                    _tickSpacing
                );

                if (lower < minLowerTick && minLowerTick < _currentTick) {
                    lower = minLowerTick;
                    upper = lower + _assetStatusUnderlying.riskParams.rangeSize * 2;
                }
            } else {
                // move to upper
                int24 maxUpperTick = calculateMaxUpperTick(
                    sqrtAssetStatus.tickUpper,
                    ScaledAsset.getAvailableCollateralValue(_token0Status),
                    availableAmount,
                    _tickSpacing
                );

                if (upper > maxUpperTick && maxUpperTick >= _currentTick) {
                    upper = maxUpperTick;
                    lower = upper - _assetStatusUnderlying.riskParams.rangeSize * 2;
                }
            }
        }

        lower = calculateUsableTick(lower, _tickSpacing);
        upper = calculateUsableTick(upper, _tickSpacing);
    }

    /**
     * @notice Returns the flag that a tick is within a range or not
     */
    function isInRange(Perp.SqrtPerpAssetStatus memory _sqrtAssetStatus) internal view returns (bool) {
        (, int24 currentTick,,,,,) = IUniswapV3Pool(_sqrtAssetStatus.uniswapPool).slot0();

        return _isInRange(_sqrtAssetStatus, currentTick);
    }

    function _isInRange(Perp.SqrtPerpAssetStatus memory _sqrtAssetStatus, int24 _currentTick)
        internal
        pure
        returns (bool)
    {
        return (_sqrtAssetStatus.tickLower <= _currentTick && _currentTick < _sqrtAssetStatus.tickUpper);
    }

    /**
     * @notice Normalizes a tick by tick spacing
     */
    function calculateUsableTick(int24 _tick, int24 _tickSpacing) internal pure returns (int24 result) {
        require(_tickSpacing > 0);

        result = _tick;

        if (result < TickMath.MIN_TICK) {
            result = TickMath.MIN_TICK;
        } else if (result > TickMath.MAX_TICK) {
            result = TickMath.MAX_TICK;
        }

        result = (result / _tickSpacing) * _tickSpacing;
    }

    /**
     * @notice The minimum tick that can be moved from the currentLowerTick, calculated from token1 amount
     */
    function calculateMinLowerTick(
        int24 _currentLowerTick,
        uint256 _available,
        uint256 _liquidityAmount,
        int24 _tickSpacing
    ) internal pure returns (int24 minLowerTick) {
        uint160 sqrtPrice =
            calculateAmount1ForLiquidity(TickMath.getSqrtRatioAtTick(_currentLowerTick), _available, _liquidityAmount);

        minLowerTick = TickMath.getTickAtSqrtRatio(sqrtPrice);

        minLowerTick += _tickSpacing;

        if (minLowerTick > _currentLowerTick - _tickSpacing) {
            minLowerTick = _currentLowerTick - _tickSpacing;
        }
    }

    /**
     * @notice The maximum tick that can be moved from the currentUpperTick, calculated from token0 amount
     */
    function calculateMaxUpperTick(
        int24 _currentUpperTick,
        uint256 _available,
        uint256 _liquidityAmount,
        int24 _tickSpacing
    ) internal pure returns (int24 maxUpperTick) {
        uint160 sqrtPrice =
            calculateAmount0ForLiquidity(TickMath.getSqrtRatioAtTick(_currentUpperTick), _available, _liquidityAmount);

        maxUpperTick = TickMath.getTickAtSqrtRatio(sqrtPrice);

        maxUpperTick -= _tickSpacing;

        if (maxUpperTick < _currentUpperTick + _tickSpacing) {
            maxUpperTick = _currentUpperTick + _tickSpacing;
        }
    }

    function calculateAmount1ForLiquidity(uint160 _sqrtRatioA, uint256 _available, uint256 _liquidityAmount)
        internal
        pure
        returns (uint160)
    {
        uint160 sqrtPrice = (_available * FixedPoint96.Q96 / _liquidityAmount).toUint160();

        if (_sqrtRatioA <= sqrtPrice + TickMath.MIN_SQRT_RATIO) {
            return TickMath.MIN_SQRT_RATIO + 1;
        }

        return _sqrtRatioA - sqrtPrice;
    }

    function calculateAmount0ForLiquidity(uint160 _sqrtRatioB, uint256 _available, uint256 _liquidityAmount)
        internal
        pure
        returns (uint160)
    {
        uint256 denominator1 = _available * _sqrtRatioB / FixedPoint96.Q96;

        if (_liquidityAmount <= denominator1) {
            return TickMath.MAX_SQRT_RATIO - 1;
        }

        uint160 sqrtPrice = uint160(_liquidityAmount * _sqrtRatioB / (_liquidityAmount - denominator1));

        if (sqrtPrice <= TickMath.MIN_SQRT_RATIO) {
            return TickMath.MIN_SQRT_RATIO + 1;
        }

        return sqrtPrice;
    }
}
