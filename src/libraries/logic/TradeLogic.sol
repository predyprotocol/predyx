// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {IHooks} from "../../interfaces/IHooks.sol";
import {ISettlement} from "../../interfaces/ISettlement.sol";
import {Perp} from "../Perp.sol";
import {Trade} from "../Trade.sol";
import {GlobalDataLibrary} from "../../types/GlobalData.sol";
import {PositionCalculator} from "../PositionCalculator.sol";

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

    function trade(
        GlobalDataLibrary.GlobalData storage globalData,
        IPredyPool.TradeParams memory tradeParams,
        ISettlement.SettlementData memory settlementData
    ) external returns (IPredyPool.TradeResult memory tradeResult) {
        Perp.PairStatus storage pairStatus = globalData.pairs[tradeParams.pairId];

        tradeResult = Trade.trade(globalData, tradeParams, settlementData);

        (tradeResult.minMargin,,, tradeResult.sqrtTwap) = PositionCalculator.calculateMinDeposit(
            pairStatus, globalData.rebalanceFeeGrowthCache, globalData.vaults[tradeParams.vaultId]
        );

        callTradeAfterCallback(globalData, tradeParams, tradeResult);

        // check vault is safe
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
            revert IPredyPool.CurrencyNotSettled();
        }

        int256 marginAmountUpdate = GlobalDataLibrary.settle(globalData, true);

        delete globalData.lockData;

        globalData.vaults[tradeParams.vaultId].margin += marginAmountUpdate;
    }
}
