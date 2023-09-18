// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {IHooks} from "../../interfaces/IHooks.sol";
import {Constants} from "../Constants.sol";
import {Perp} from "../Perp.sol";
import {Trade} from "../Trade.sol";
import {GlobalDataLibrary} from "../../types/GlobalData.sol";
import {PositionCalculator} from "../PositionCalculator.sol";
import "forge-std/console2.sol";

library LiquidationLogic {
    // 5%
    uint256 constant _MAX_SLIPPAGE = 500;
    // 0.5%
    uint256 constant _MIN_SLIPPAGE = 50;

    function liquidate(
        uint256 vaultId,
        uint256 closeRatio,
        GlobalDataLibrary.GlobalData storage globalData,
        bytes memory settlementData
    ) external returns (IPredyPool.TradeResult memory tradeResult) {
        Perp.UserStatus memory openPosition = globalData.vaults[vaultId].openPosition;
        Perp.PairStatus storage pairStatus = globalData.pairs[openPosition.pairId];

        (bool isLiquidatable, int256 minDeposit, int256 vaultValue, uint256 twap) = PositionCalculator.isLiquidatable(
            pairStatus, globalData.rebalanceFeeGrowthCache, globalData.vaults[vaultId]
        );

        console2.log(uint256(minDeposit), uint256(vaultValue));

        if (!isLiquidatable) {
            revert IPredyPool.VaultIsNotDanger();
        }

        tradeResult = Trade.trade(
            globalData,
            IPredyPool.TradeParams(
                openPosition.pairId, vaultId, -openPosition.perp.amount, -openPosition.sqrtPerp.amount, ""
            ),
            settlementData
        );

        delete globalData.lockData;

        (tradeResult.minDeposit,,,) = PositionCalculator.calculateMinDeposit(
            pairStatus, globalData.rebalanceFeeGrowthCache, globalData.vaults[vaultId]
        );

        // TODO: compare tradeResult.averagePrice and TWAP
        checkPrice(twap, tradeResult.averagePrice, calculateSlippageTolerance(minDeposit, vaultValue));
    }

    function calculateSlippageTolerance(int256 minDeposit, int256 vaultValue) internal pure returns (uint256) {
        if (vaultValue <= 0 || minDeposit == 0) {
            return _MAX_SLIPPAGE;
        }

        uint256 ratio = uint256(vaultValue * 1e4 / minDeposit);

        if (ratio > 1e4) {
            return _MIN_SLIPPAGE;
        }

        return (_MAX_SLIPPAGE - ratio * (_MAX_SLIPPAGE - _MIN_SLIPPAGE) / 1e4) + 1e4;
    }

    function checkPrice(uint256 sqrtTwap, int256 averagePrice, uint256 slippageTolerance) internal pure {
        uint256 twap = (sqrtTwap * sqrtTwap) >> Constants.RESOLUTION;

        if (averagePrice == 0) {
            //TODO: revert
        }

        if (averagePrice > 0) {
            if (twap * 1e4 / slippageTolerance > uint256(averagePrice)) {
                revert IPredyPool.SlippageTooLarge();
            }
        } else if (averagePrice < 0) {
            if (twap * slippageTolerance / 1e4 < uint256(-averagePrice)) {
                revert IPredyPool.SlippageTooLarge();
            }
        }
    }
}
