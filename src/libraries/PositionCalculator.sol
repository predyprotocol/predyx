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
import "forge-std/console2.sol";

library PositionCalculator {
    using ScaledAsset for ScaledAsset.AssetStatus;
    using SafeCast for uint256;

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
    ) internal view returns (bool _isLiquidatable, int256 minMargin, int256 vaultValue, uint160 twap) {
        bool hasPosition;

        (minMargin, vaultValue, hasPosition, twap) = calculateMinDeposit(pairStatus, _rebalanceFeeGrowthCache, _vault);

        console2.log(vaultValue);
        console2.log(minMargin);

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

        require(isSafe, "NS");
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
    ) internal view returns (int256 minMargin, int256 vaultValue, bool hasPosition, uint160 twap) {
        int256 minValue;
        uint256 debtValue;

        twap = getSqrtPrice(pairStatus.sqrtAssetStatus.uniswapPool, pairStatus.isMarginZero);

        (minValue, vaultValue, debtValue, hasPosition) = calculateMinValue(
            vault,
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
     * @param vault The target vault for calculation
     * @param positionParams The position parameters
     * @param sqrtPrice The square root of time-weighted average price
     * @param riskRatio risk ratio of price
     */
    function calculateMinValue(
        DataType.Vault memory vault,
        PositionParams memory positionParams,
        uint160 sqrtPrice,
        uint256 riskRatio
    ) internal pure returns (int256 minValue, int256 vaultValue, uint256 debtValue, bool hasPosition) {
        Perp.UserStatus memory userStatus = vault.openPosition;

        minValue += calculateMinValue(sqrtPrice, positionParams, riskRatio);

        vaultValue += calculateValue(sqrtPrice, positionParams);

        debtValue += calculateSquartDebtValue(sqrtPrice, userStatus);

        hasPosition = hasPosition || getHasPositionFlag(userStatus);

        minValue += int256(vault.margin);
        vaultValue += int256(vault.margin);
    }

    function getHasPosition(DataType.Vault memory _vault) internal pure returns (bool hasPosition) {
        Perp.UserStatus memory userStatus = _vault.openPosition;

        hasPosition = hasPosition || getHasPositionFlag(userStatus);
    }

    function getSqrtPrice(address _uniswapPool, bool _isMarginZero) internal view returns (uint160 sqrtPriceX96) {
        return UniHelper.convertSqrtPrice(UniHelper.getSqrtTWAP(_uniswapPool), _isMarginZero);
    }

    function getPositionWithUnrealizedFee(
        Perp.PairStatus memory _underlyingAsset,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage _rebalanceFeeGrowthCache,
        Perp.UserStatus memory _perpUserStatus
    ) internal view returns (PositionParams memory positionParams) {
        (int256 unrealizedFeeUnderlying, int256 unrealizedFeeStable) =
            PerpFee.computeUserFee(_underlyingAsset, _rebalanceFeeGrowthCache, _perpUserStatus);

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

    function getHasPositionFlag(Perp.UserStatus memory _perpUserStatus) internal pure returns (bool) {
        return _perpUserStatus.stable.positionAmount < 0 || _perpUserStatus.sqrtPerp.amount < 0
            || _perpUserStatus.underlying.positionAmount < 0;
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

    function calculateSquartDebtValue(uint256 _sqrtPrice, Perp.UserStatus memory _perpUserStatus)
        internal
        pure
        returns (uint256)
    {
        int256 squartPosition = _perpUserStatus.sqrtPerp.amount;

        if (squartPosition > 0) {
            return 0;
        }

        return (2 * (uint256(-squartPosition) * _sqrtPrice) >> Constants.RESOLUTION);
    }
}
