// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {IHooks} from "../../interfaces/IHooks.sol";
import {ISettlement} from "../../interfaces/ISettlement.sol";
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

    // 5%
    uint256 constant _MAX_SLIPPAGE = 500;
    // 0.5%
    uint256 constant _MIN_SLIPPAGE = 50;

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

        // Checks the vault is danger
        (uint160 sqrtTwap, uint256 slippageTolerance) =
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
        checkPrice(sqrtTwap, tradeParams, tradeResult, slippageTolerance);

        if (!hasPosition) {
            if (vault.margin > 0) {
                // Send the remaining margin to the recipient.
                IERC20(pairStatus.quotePool.token).transfer(vault.recepient, uint256(vault.margin));
            } else if (vault.margin < 0) {
                // If the margin is negative, the liquidator will make up for it.
                IERC20(pairStatus.quotePool.token).transferFrom(msg.sender, address(this), uint256(-vault.margin));
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
    ) internal view returns (uint160 sqrtTwap, uint256 slippageTolerance) {
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

    function checkPrice(
        uint256 sqrtTwap,
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult,
        uint256 slippageTolerance
    ) internal pure {
        if (tradeParams.tradeAmount != 0) {
            uint256 twap = (sqrtTwap * sqrtTwap) >> Constants.RESOLUTION;
            int256 closePrice = (
                (tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff) * int256(Constants.Q96)
            ) / tradeParams.tradeAmount;

            if (closePrice > 0) {
                if (twap * 1e4 / slippageTolerance > uint256(closePrice)) {
                    revert IPredyPool.SlippageTooLarge();
                }
            } else if (closePrice < 0) {
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
                if (sqrtTwap * 1e4 / slippageTolerance > uint256(closeSqrtPrice)) {
                    revert IPredyPool.SlippageTooLarge();
                }
            } else if (closeSqrtPrice < 0) {
                if (sqrtTwap * slippageTolerance / 1e4 < uint256(-closeSqrtPrice)) {
                    revert IPredyPool.SlippageTooLarge();
                }
            }
        }
    }
}
