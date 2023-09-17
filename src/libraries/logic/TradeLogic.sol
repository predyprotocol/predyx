// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {IHooks} from "../../interfaces/IHooks.sol";
import {Perp} from "../Perp.sol";
import {Trade} from "../Trade.sol";
import {GlobalDataLibrary} from "../../types/GlobalData.sol";
import {PositionCalculator} from "../PositionCalculator.sol";

library TradeLogic {
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;

    function trade(
        GlobalDataLibrary.GlobalData storage globalData,
        IPredyPool.TradeParams memory tradeParams,
        bytes memory settlementData
    ) external returns (IPredyPool.TradeResult memory tradeResult) {
        Perp.PairStatus storage pairStatus = globalData.pairs[tradeParams.pairId];

        tradeResult = Trade.trade(globalData, tradeParams, settlementData);

        _callTradeAfterCallback(globalData, tradeParams, tradeResult);

        // check vault is safe
        tradeResult.minDeposit = PositionCalculator.checkSafe(
            pairStatus, globalData.rebalanceFeeGrowthCache, globalData.vaults[tradeParams.vaultId]
        );
    }

    function _callTradeAfterCallback(
        GlobalDataLibrary.GlobalData storage globalData,
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) internal {
        IHooks(msg.sender).predyTradeAfterCallback(tradeParams, tradeResult);

        if (globalData.settle(false) != 0) {
            revert IPredyPool.CurrencyNotSettled();
        }

        int256 marginAmountUpdate = GlobalDataLibrary.settle(globalData, true);

        delete globalData.lockData;

        globalData.vaults[tradeParams.vaultId].margin += marginAmountUpdate;
    }
}
