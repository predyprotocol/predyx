// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {IHooks} from "../../interfaces/IHooks.sol";
import {ISettlement} from "../../interfaces/ISettlement.sol";
import {ApplyInterestLib} from "../ApplyInterestLib.sol";
import {Perp} from "../Perp.sol";
import {Trade} from "../Trade.sol";
import {GlobalDataLibrary} from "../../types/GlobalData.sol";
import {PositionCalculator} from "../PositionCalculator.sol";
import {ScaledAsset} from "../ScaledAsset.sol";

library TradeLogic {
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;

    event PositionUpdated(
        uint256 vaultId,
        uint256 pairId,
        int256 tradeAmount,
        int256 tradeSqrtAmount,
        IPredyPool.Payoff payoff,
        int256 fee
    );

    function batchTrade(
        GlobalDataLibrary.GlobalData storage globalData,
        IPredyPool.TradeParams[] memory tradeParamsList,
        ISettlement.SettlementData[] memory settlementDataList
    ) public returns (IPredyPool.TradeResult[] memory tradeResult) {
        tradeResult = new IPredyPool.TradeResult[](tradeParamsList.length);

        for (uint256 i = 0; i < tradeParamsList.length; i++) {
            IPredyPool.TradeParams memory tradeParams = tradeParamsList[i];

            Perp.PairStatus storage pairStatus = globalData.pairs[tradeParams.pairId];

            // update interest growth
            ApplyInterestLib.applyInterestForToken(globalData.pairs, tradeParams.pairId);

            tradeResult[i] = Trade.trade(globalData, tradeParams, settlementDataList[i]);

            globalData.vaults[tradeParams.vaultId].margin +=
                tradeResult[i].fee + tradeResult[i].payoff.perpPayoff + tradeResult[i].payoff.sqrtPayoff;

            (tradeResult[i].minMargin,,, tradeResult[i].sqrtTwap) = PositionCalculator.calculateMinDeposit(
                pairStatus, globalData.rebalanceFeeGrowthCache, globalData.vaults[tradeParams.vaultId]
            );

            callTradeAfterCallback(globalData, tradeParams, tradeResult[i]);

            // check vault is safe
            tradeResult[i].minMargin = PositionCalculator.checkSafe(
                pairStatus, globalData.rebalanceFeeGrowthCache, globalData.vaults[tradeParams.vaultId]
            );

            emit PositionUpdated(
                tradeParams.vaultId,
                tradeParams.pairId,
                tradeParams.tradeAmount,
                tradeParams.tradeAmountSqrt,
                tradeResult[i].payoff,
                tradeResult[i].fee
            );
        }

        for (uint256 i = 0; i < tradeParamsList.length; i++) {
            IPredyPool.TradeParams memory tradeParams = tradeParamsList[i];

            Perp.PairStatus storage pairStatus = globalData.pairs[tradeParams.pairId];

            ScaledAsset.validateAvailability(pairStatus.quotePool.tokenStatus);
            ScaledAsset.validateAvailability(pairStatus.basePool.tokenStatus);
        }
    }

    function callTradeAfterCallback(
        GlobalDataLibrary.GlobalData storage globalData,
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) internal {
        globalData.initializeLock(tradeParams.pairId, msg.sender);

        IHooks(msg.sender).predyTradeAfterCallback(tradeParams, tradeResult);

        if (globalData.settle(false) != 0) {
            revert IPredyPool.CurrencyNotSettled();
        }

        int256 marginAmountUpdate = GlobalDataLibrary.settle(globalData, true);

        delete globalData.lockData;

        globalData.vaults[tradeParams.vaultId].margin += marginAmountUpdate;
    }
}
