// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {IHooks} from "../../interfaces/IHooks.sol";
import {ISettlement} from "../../interfaces/ISettlement.sol";
import {ApplyInterestLib} from "../ApplyInterestLib.sol";
import {DataType} from "../DataType.sol";
import {Perp} from "../Perp.sol";
import {Trade} from "../Trade.sol";
import {GlobalDataLibrary} from "../../types/GlobalData.sol";
import {PositionCalculator} from "../PositionCalculator.sol";
import {ScaledAsset} from "../ScaledAsset.sol";

library TradeLogic {
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;

    event MarginUpdated(uint256 indexed vaultId, int256 updatedMarginAmount);

    event PositionUpdated(
        uint256 indexed vaultId,
        uint256 pairId,
        int256 tradeAmount,
        int256 tradeSqrtAmount,
        IPredyPool.Payoff payoff,
        int256 fee
    );

    function trade(
        GlobalDataLibrary.GlobalData storage globalData,
        IPredyPool.TradeParams memory tradeParams,
        ISettlement.SettlementData memory settlementData
    ) external returns (IPredyPool.TradeResult memory tradeResult) {
        DataType.PairStatus storage pairStatus = globalData.pairs[tradeParams.pairId];

        // update interest growth
        ApplyInterestLib.applyInterestForToken(globalData.pairs, tradeParams.pairId);

        tradeResult = Trade.trade(globalData, tradeParams, settlementData);

        globalData.vaults[tradeParams.vaultId].margin +=
            tradeResult.fee + tradeResult.payoff.perpPayoff + tradeResult.payoff.sqrtPayoff;

        (tradeResult.minMargin,,, tradeResult.sqrtTwap) = PositionCalculator.calculateMinDeposit(
            pairStatus, globalData.rebalanceFeeGrowthCache, globalData.vaults[tradeParams.vaultId]
        );

        // The caller deposits or withdraws margin from the callback that is called below.
        callTradeAfterCallback(globalData, tradeParams, tradeResult);

        // check vault safety
        tradeResult.minMargin = PositionCalculator.checkSafe(
            pairStatus, globalData.rebalanceFeeGrowthCache, globalData.vaults[tradeParams.vaultId]
        );

        emit PositionUpdated(
            tradeParams.vaultId,
            tradeParams.pairId,
            tradeParams.tradeAmount,
            tradeParams.tradeAmountSqrt,
            tradeResult.payoff,
            tradeResult.fee
        );
    }

    function callTradeAfterCallback(
        GlobalDataLibrary.GlobalData storage globalData,
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) internal {
        globalData.initializeLock(tradeParams.pairId, msg.sender);

        IHooks(msg.sender).predyTradeAfterCallback(tradeParams, tradeResult);

        if (globalData.settle(false) != 0) {
            revert IPredyPool.BaseTokenNotSettled();
        }

        int256 marginAmountUpdate = GlobalDataLibrary.settle(globalData, true);

        delete globalData.lockData;

        globalData.vaults[tradeParams.vaultId].margin += marginAmountUpdate;

        emit MarginUpdated(tradeParams.vaultId, marginAmountUpdate);
    }
}
