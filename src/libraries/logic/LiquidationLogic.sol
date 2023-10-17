// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {IHooks} from "../../interfaces/IHooks.sol";
import {ISettlement} from "../../interfaces/ISettlement.sol";
import {ApplyInterestLib} from "../ApplyInterestLib.sol";
import {Constants} from "../Constants.sol";
import {Perp} from "../Perp.sol";
import {Trade} from "../Trade.sol";
import {Math} from "../math/Math.sol";
import {DataType} from "../DataType.sol";
import {GlobalDataLibrary} from "../../types/GlobalData.sol";
import {PositionCalculator} from "../PositionCalculator.sol";

library LiquidationLogic {
    using Math for int256;
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;

    error SlippageTooLarge();

    error OutOfAcceptablePriceRange();

    // 5%
    uint256 constant _MAX_SLIPPAGE = 500;
    // 0.5%
    uint256 constant _MIN_SLIPPAGE = 50;

    // 3% scaled by 1e8
    uint256 constant _MAX_ACCEPTABLE_SQRT_PRICE_RANGE = 101488915;

    event PositionLiquidated(
        uint256 vaultId,
        uint256 pairId,
        int256 tradeAmount,
        int256 tradeSqrtAmount,
        IPredyPool.Payoff payoff,
        int256 fee
    );

    function liquidate(
        uint256 vaultId,
        uint256 closeRatio,
        GlobalDataLibrary.GlobalData storage globalData,
        ISettlement.SettlementData memory settlementData
    ) external returns (IPredyPool.TradeResult memory tradeResult) {
        require(closeRatio > 0);
        DataType.Vault storage vault = globalData.vaults[vaultId];
        Perp.PairStatus storage pairStatus = globalData.pairs[vault.openPosition.pairId];

        // update interest growth
        ApplyInterestLib.applyInterestForToken(globalData.pairs, vault.openPosition.pairId);

        // Checks the vault is danger
        (uint256 sqrtTwap, uint256 slippageTolerance) =
            checkVaultIsDanger(pairStatus, vault, globalData.rebalanceFeeGrowthCache);

        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            vault.openPosition.pairId,
            vaultId,
            -vault.openPosition.perp.amount * int256(closeRatio) / 1e18,
            -vault.openPosition.sqrtPerp.amount * int256(closeRatio) / 1e18,
            ""
        );

        tradeResult = Trade.trade(globalData, tradeParams, settlementData);

        vault.margin += tradeResult.fee + tradeResult.payoff.perpPayoff + tradeResult.payoff.sqrtPayoff;

        tradeResult.sqrtTwap = sqrtTwap;

        bool hasPosition;

        (tradeResult.minMargin,, hasPosition,) =
            PositionCalculator.calculateMinDeposit(pairStatus, globalData.rebalanceFeeGrowthCache, vault);

        // TODO: compare tradeResult.averagePrice and TWAP, which averagePrice or entryPrice is better?
        checkPrice(sqrtTwap, tradeResult, slippageTolerance);

        if (!hasPosition) {
            int256 remainingMargin = vault.margin;

            if (remainingMargin > 0) {
                // Send the remaining margin to the recipient.
                if (vault.recepient != address(0)) {
                    vault.margin = 0;

                    TransferHelper.safeTransfer(pairStatus.quotePool.token, vault.recepient, uint256(remainingMargin));
                }
            } else if (remainingMargin < 0) {
                vault.margin = 0;

                // If the margin is negative, the liquidator will make up for it.
                IERC20(pairStatus.quotePool.token).transferFrom(msg.sender, address(this), uint256(-remainingMargin));
            }
        }
    }

    /**
     * @notice Check vault safety and get slippage tolerance
     * @param pairStatus The pair status
     * @param vault The vault object
     * @param rebalanceFeeGrowthCache rebalance fee growth
     * @return sqrtTwap The square root of time weighted average price used for value calculation
     * @return slippageTolerance slippage tolerance calculated by minMargin and vault value
     */
    function checkVaultIsDanger(
        Perp.PairStatus memory pairStatus,
        DataType.Vault memory vault,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage rebalanceFeeGrowthCache
    ) internal view returns (uint256 sqrtTwap, uint256 slippageTolerance) {
        bool isLiquidatable;
        int256 minMargin;
        int256 vaultValue;

        (isLiquidatable, minMargin, vaultValue, sqrtTwap) =
            PositionCalculator.isLiquidatable(pairStatus, rebalanceFeeGrowthCache, vault);

        if (!isLiquidatable) {
            revert IPredyPool.VaultIsNotDanger();
        }

        slippageTolerance = calculateSlippageTolerance(minMargin, vaultValue);
    }

    function calculateSlippageTolerance(int256 minMargin, int256 vaultValue) internal pure returns (uint256) {
        if (vaultValue <= 0 || minMargin == 0) {
            return _MAX_SLIPPAGE;
        }

        uint256 ratio = uint256(vaultValue * 1e4 / minMargin);

        if (ratio > 1e4) {
            return _MIN_SLIPPAGE;
        }

        return (_MAX_SLIPPAGE - ratio * (_MAX_SLIPPAGE - _MIN_SLIPPAGE) / 1e4) + 1e4;
    }

    function checkPrice(uint256 sqrtTwap, IPredyPool.TradeResult memory tradeResult, uint256 slippageTolerance)
        internal
        pure
    {
        uint256 twap = (sqrtTwap * sqrtTwap) >> Constants.RESOLUTION;

        if (tradeResult.averagePrice > 0) {
            // long
            if (twap * 1e4 / slippageTolerance > uint256(tradeResult.averagePrice)) {
                revert SlippageTooLarge();
            }
        } else if (tradeResult.averagePrice < 0) {
            // short
            if (twap * slippageTolerance / 1e4 < uint256(-tradeResult.averagePrice)) {
                revert SlippageTooLarge();
            }
        }

        if (
            tradeResult.sqrtPrice < sqrtTwap * 1e8 / _MAX_ACCEPTABLE_SQRT_PRICE_RANGE
                || sqrtTwap * _MAX_ACCEPTABLE_SQRT_PRICE_RANGE / 1e8 < tradeResult.sqrtPrice
        ) {
            revert OutOfAcceptablePriceRange();
        }

        /*
        if (tradeParams.tradeAmount != 0) {
            uint256 twap = (sqrtTwap * sqrtTwap) >> Constants.RESOLUTION;
            int256 closePrice = (
                int256(Math.abs(tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff) * Constants.Q96)
            ) / tradeParams.tradeAmount;

            if (closePrice > 0) {
                // long
                if (twap * 1e4 / slippageTolerance > uint256(closePrice)) {
                    revert IPredyPool.SlippageTooLarge();
                }
            } else if (closePrice < 0) {
                // short
                if (twap * slippageTolerance / 1e4 < uint256(-closePrice)) {
                    revert IPredyPool.SlippageTooLarge();
                }
            }
        }

        if (tradeParams.tradeAmountSqrt != 0) {
            int256 closeSqrtPrice = (
                (tradeResult.payoff.sqrtEntryUpdate + tradeResult.payoff.sqrtPayoff) * int256(Constants.Q96)
            ) / tradeParams.tradeAmountSqrt;

            if (closeSqrtPrice > 0) {
                // long
                if (sqrtTwap * 1e4 / slippageTolerance > uint256(closeSqrtPrice)) {
                    revert IPredyPool.SlippageTooLarge();
                }
            } else if (closeSqrtPrice < 0) {
                // short
                if (sqrtTwap * slippageTolerance / 1e4 < uint256(-closeSqrtPrice)) {
                    revert IPredyPool.SlippageTooLarge();
                }
            }
        }
        */
    }
}
