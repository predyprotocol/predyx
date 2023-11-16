// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./UniHelper.sol";
import "./Perp.sol";
import "./DataType.sol";
import "./Constants.sol";
import "./PerpFee.sol";
import "./math/Math.sol";
import "../PriceFeed.sol";

library PositionCalculator {
    using ScaledAsset for ScaledAsset.AssetStatus;
    using SafeCast for uint256;

    error NotSafe();

    uint256 internal constant RISK_RATIO_ONE = 1e8;

    struct PositionParams {
        // x^0
        int256 amountStable;
        // 2x^0.5
        int256 amountSqrt;
        // x^1
        int256 amountUnderlying;
    }

    function isLiquidatable(
        Perp.PairStatus memory pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault memory _vault
    ) internal view returns (bool _isLiquidatable, int256 minMargin, int256 vaultValue, uint256 twap) {
        bool hasPosition;

        (minMargin, vaultValue, hasPosition, twap) = calculateMinDeposit(pairStatus, _rebalanceFeeGrowthCache, _vault);

        bool isSafe = vaultValue >= minMargin && _vault.margin >= 0;

        _isLiquidatable = !isSafe && hasPosition;
    }

    function checkSafe(
        Perp.PairStatus memory pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault memory _vault
    ) internal view returns (int256 minMargin) {
        bool isSafe;

        (minMargin, isSafe,) = getIsSafe(pairStatus, _rebalanceFeeGrowthCache, _vault);

        if (!isSafe) {
            revert NotSafe();
        }
    }

    function getIsSafe(
        Perp.PairStatus memory pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault memory _vault
    ) internal view returns (int256 minMargin, bool isSafe, bool hasPosition) {
        int256 vaultValue;

        (minMargin, vaultValue, hasPosition,) = calculateMinDeposit(pairStatus, _rebalanceFeeGrowthCache, _vault);

        isSafe = vaultValue >= minMargin && _vault.margin >= 0;
    }

    function calculateMinDeposit(
        Perp.PairStatus memory pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        DataType.Vault memory vault
    ) internal view returns (int256 minMargin, int256 vaultValue, bool hasPosition, uint256 twap) {
        int256 minValue;
        uint256 debtValue;

        twap = getSqrtIndexPrice(pairStatus);

        (minValue, vaultValue, debtValue, hasPosition) = calculateMinValue(
            vault.margin,
            getPositionWithUnrealizedFee(pairStatus, _rebalanceFeeGrowthCache, vault.openPosition),
            twap,
            pairStatus.riskParams.riskRatio
        );

        int256 minMinValue = SafeCast.toInt256(calculateRequiredCollateralWithDebt() * debtValue / 1e6);

        minMargin = vaultValue - minValue + minMinValue;

        if (hasPosition && minMargin < Constants.MIN_MARGIN_AMOUNT) {
            minMargin = Constants.MIN_MARGIN_AMOUNT;
        }
    }

    function calculateRequiredCollateralWithDebt() internal pure returns (uint256) {
        return Constants.BASE_MIN_COLLATERAL_WITH_DEBT;
    }

    /**
     * @notice Calculates min value of the vault.
     * @param marginAmount The target vault for calculation
     * @param positionParams The position parameters
     * @param sqrtPrice The square root of time-weighted average price
     * @param riskRatio risk ratio of price
     */
    function calculateMinValue(
        int256 marginAmount,
        PositionParams memory positionParams,
        uint256 sqrtPrice,
        uint256 riskRatio
    ) internal pure returns (int256 minValue, int256 vaultValue, uint256 debtValue, bool hasPosition) {
        minValue += calculateMinValue(sqrtPrice, positionParams, riskRatio);

        vaultValue += calculateValue(sqrtPrice, positionParams);

        debtValue += calculateSquartDebtValue(sqrtPrice, positionParams);

        hasPosition = hasPosition || getHasPositionFlag(positionParams);

        minValue += marginAmount;
        vaultValue += marginAmount;
    }

    function getHasPosition(DataType.Vault memory _vault) internal pure returns (bool hasPosition) {
        Perp.UserStatus memory userStatus = _vault.openPosition;

        hasPosition = hasPosition || getHasPositionFlag(getPosition(userStatus));
    }

    function getSqrtIndexPrice(Perp.PairStatus memory pairStatus) internal view returns (uint256 sqrtPriceX96) {
        if (pairStatus.priceFeed != address(0)) {
            return PriceFeed(pairStatus.priceFeed).getSqrtPrice();
        } else {
            return UniHelper.convertSqrtPrice(
                UniHelper.getSqrtTWAP(pairStatus.sqrtAssetStatus.uniswapPool), pairStatus.isMarginZero
            );
        }
    }

    function getPositionWithUnrealizedFee(
        Perp.PairStatus memory pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus memory _perpUserStatus
    ) internal view returns (PositionParams memory positionParams) {
        (int256 unrealizedFeeUnderlying, int256 unrealizedFeeStable) =
            PerpFee.computeUserFee(pairStatus, _rebalanceFeeGrowthCache, _perpUserStatus);

        return PositionParams(
            _perpUserStatus.perp.entryValue + _perpUserStatus.sqrtPerp.entryValue + unrealizedFeeStable,
            _perpUserStatus.sqrtPerp.amount,
            _perpUserStatus.perp.amount + unrealizedFeeUnderlying
        );
    }

    function getPosition(Perp.UserStatus memory _perpUserStatus)
        internal
        pure
        returns (PositionParams memory positionParams)
    {
        return PositionParams(
            _perpUserStatus.perp.entryValue + _perpUserStatus.sqrtPerp.entryValue,
            _perpUserStatus.sqrtPerp.amount,
            _perpUserStatus.perp.amount
        );
    }

    function getHasPositionFlag(PositionParams memory _positionParams) internal pure returns (bool) {
        return _positionParams.amountSqrt != 0 || _positionParams.amountUnderlying != 0;
    }

    /**
     * @notice Calculates min position value in the range `p/r` to `rp`.
     * MinValue := Min(v(rp), v(p/r), v((b/a)^2))
     * where `a` is underlying asset amount, `b` is Sqrt perp amount
     * and `c` is Stable asset amount.
     * r is risk parameter.
     */
    function calculateMinValue(uint256 _sqrtPrice, PositionParams memory _positionParams, uint256 _riskRatio)
        internal
        pure
        returns (int256 minValue)
    {
        minValue = type(int256).max;

        uint256 upperPrice = _sqrtPrice * _riskRatio / RISK_RATIO_ONE;
        uint256 lowerPrice = _sqrtPrice * RISK_RATIO_ONE / _riskRatio;

        {
            int256 v = calculateValue(upperPrice, _positionParams);
            if (v < minValue) {
                minValue = v;
            }
        }

        {
            int256 v = calculateValue(lowerPrice, _positionParams);
            if (v < minValue) {
                minValue = v;
            }
        }

        if (_positionParams.amountSqrt < 0 && _positionParams.amountUnderlying > 0) {
            uint256 minSqrtPrice =
                (uint256(-_positionParams.amountSqrt) * Constants.Q96) / uint256(_positionParams.amountUnderlying);

            if (lowerPrice < minSqrtPrice && minSqrtPrice < upperPrice) {
                int256 v = calculateValue(minSqrtPrice, _positionParams);

                if (v < minValue) {
                    minValue = v;
                }
            }
        }
    }

    /**
     * @notice Calculates position value.
     * PositionValue = a * x+2 * b * sqrt(x) + c.
     * where `a` is underlying asset amount, `b` is liquidity amount of Uni LP Position
     * and `c` is Stable asset amount
     */
    function calculateValue(uint256 _sqrtPrice, PositionParams memory _positionParams) internal pure returns (int256) {
        uint256 price = (_sqrtPrice * _sqrtPrice) >> Constants.RESOLUTION;

        return ((_positionParams.amountUnderlying * price.toInt256()) / int256(Constants.Q96))
            + (2 * (_positionParams.amountSqrt * _sqrtPrice.toInt256()) / int256(Constants.Q96))
            + _positionParams.amountStable;
    }

    function calculateSquartDebtValue(uint256 _sqrtPrice, PositionParams memory positionParams)
        internal
        pure
        returns (uint256)
    {
        int256 squartPosition = positionParams.amountSqrt;

        if (squartPosition > 0) {
            return 0;
        }

        return (2 * (uint256(-squartPosition) * _sqrtPrice) >> Constants.RESOLUTION);
    }
}
