// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";
import "../../../src/libraries/PositionCalculator.sol";

contract CalculateMinDepositTest is TestPositionCalculator {
    Perp.PairStatus pairStatus;
    mapping(uint256 => DataType.RebalanceFeeGrowthCache) internal rebalanceFeeGrowthCache;

    function setUp() public override {
        TestPositionCalculator.setUp();

        pairStatus = createAssetStatus(1, address(usdc), address(weth), address(uniswapPool));
    }

    function getVault(int256 _amountStable, int256 _amountSquart, int256 _amountUnderlying, int256 _margin)
        internal
        view
        returns (DataType.Vault memory)
    {
        Perp.UserStatus memory openPosition = Perp.createPerpUserStatus(2);

        openPosition.sqrtPerp.amount = _amountSquart;
        openPosition.underlying.positionAmount = _amountUnderlying;
        openPosition.perp.amount = _amountUnderlying;

        openPosition.perp.entryValue = _amountStable;
        openPosition.sqrtPerp.entryValue = 0;
        openPosition.stable.positionAmount = _amountStable;

        return DataType.Vault(1, address(usdc), address(this), _margin, openPosition);
    }

    function testCalculateMinDepositZero() public {
        (int256 minDeposit, int256 vaultValue, bool hasPosition,) =
            PositionCalculator.calculateMinDeposit(pairStatus, rebalanceFeeGrowthCache, getVault(0, 0, 0, 0));

        assertEq(minDeposit, 0);
        assertEq(vaultValue, 0);
        assertFalse(hasPosition);
    }

    function testCalculateMinDepositStable(uint256 _amountStable) public {
        int256 amountStable = int256(bound(_amountStable, 0, 1e36));

        (int256 minDeposit, int256 vaultValue, bool hasPosition,) =
            PositionCalculator.calculateMinDeposit(pairStatus, rebalanceFeeGrowthCache, getVault(amountStable, 0, 0, 0));

        assertEq(minDeposit, 0);
        assertEq(vaultValue, amountStable);
        assertFalse(hasPosition);
    }

    function testCalculateMinDepositDeltaLong() public {
        DataType.Vault memory vault = getVault(-1000, 0, 1000, 0);

        (int256 minDeposit, int256 vaultValue, bool hasPosition,) =
            PositionCalculator.calculateMinDeposit(pairStatus, rebalanceFeeGrowthCache, vault);

        assertEq(minDeposit, 1000000);
        assertEq(vaultValue, 0);
        assertTrue(hasPosition);

        (, bool isSafe,) = PositionCalculator.getIsSafe(pairStatus, rebalanceFeeGrowthCache, vault);

        assertFalse(isSafe);
    }

    function testCalculateMinDepositGammaShort() public {
        DataType.Vault memory vault = getVault(-2 * 1e8, 1e8, 0, 0);
        (int256 minDeposit, int256 vaultValue, bool hasPosition,) =
            PositionCalculator.calculateMinDeposit(pairStatus, rebalanceFeeGrowthCache, vault);

        assertEq(minDeposit, 17425814);
        assertEq(vaultValue, 0);
        assertTrue(hasPosition);

        (, bool isSafe,) = PositionCalculator.getIsSafe(pairStatus, rebalanceFeeGrowthCache, vault);
        (bool isLiquidatable,,,) = PositionCalculator.isLiquidatable(pairStatus, rebalanceFeeGrowthCache, vault);

        assertFalse(isSafe);
        assertTrue(isLiquidatable);
    }

    function testCalculateMinDepositGammaShortSafe() public {
        DataType.Vault memory vault = getVault(-2 * 1e8, 1e8, 0, 20000000);
        (int256 minDeposit, int256 vaultValue, bool hasPosition,) =
            PositionCalculator.calculateMinDeposit(pairStatus, rebalanceFeeGrowthCache, vault);

        assertEq(minDeposit, 17425814);
        assertEq(vaultValue, 20000000);
        assertTrue(hasPosition);

        (, bool isSafe,) = PositionCalculator.getIsSafe(pairStatus, rebalanceFeeGrowthCache, vault);
        assertTrue(isSafe);
    }

    function testCalculateMinDepositGammaLong() public {
        DataType.Vault memory vault = getVault(2 * 1e8, -1e8, 0, 0);
        (int256 minDeposit, int256 vaultValue, bool hasPosition,) =
            PositionCalculator.calculateMinDeposit(pairStatus, rebalanceFeeGrowthCache, vault);

        assertEq(minDeposit, 19489021);
        assertEq(vaultValue, 0);
        assertTrue(hasPosition);

        (, bool isSafe,) = PositionCalculator.getIsSafe(pairStatus, rebalanceFeeGrowthCache, vault);
        (bool isLiquidatable,,,) = PositionCalculator.isLiquidatable(pairStatus, rebalanceFeeGrowthCache, vault);

        assertFalse(isSafe);
        assertTrue(isLiquidatable);
    }

    function testCalculateMinDepositGammaLongSafe() public {
        DataType.Vault memory vault = getVault(2 * 1e8, -1e8, 0, 22000000);
        (int256 minDeposit, int256 vaultValue, bool hasPosition,) =
            PositionCalculator.calculateMinDeposit(pairStatus, rebalanceFeeGrowthCache, vault);

        assertEq(minDeposit, 19489021);
        assertEq(vaultValue, 22000000);
        assertTrue(hasPosition);

        (, bool isSafe,) = PositionCalculator.getIsSafe(pairStatus, rebalanceFeeGrowthCache, vault);
        assertTrue(isSafe);
    }

    function testMarginIsNegative() public {
        DataType.Vault memory vault = getVault(0, 0, 0, -100);

        (, bool isSafe,) = PositionCalculator.getIsSafe(pairStatus, rebalanceFeeGrowthCache, vault);
        (bool isLiquidatable,,,) = PositionCalculator.isLiquidatable(pairStatus, rebalanceFeeGrowthCache, vault);

        assertFalse(isSafe);
        assertFalse(isLiquidatable);
    }
}
