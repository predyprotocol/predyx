// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import {ISettlement} from "../../interfaces/ISettlement.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {DataType} from "../DataType.sol";
import {Perp} from "../Perp.sol";
import {PairLib} from "../PairLib.sol";
import {ApplyInterestLib} from "../ApplyInterestLib.sol";
import {GlobalDataLibrary} from "../../types/GlobalData.sol";

library ReallocationLogic {
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;

    function reallocate(
        GlobalDataLibrary.GlobalData storage globalData,
        uint256 pairId,
        ISettlement.SettlementData memory settlementData
    ) external returns (bool relocationOccurred) {
        // Checks the pair exists
        globalData.validate(pairId);

        // Updates interest rate related to the pair
        ApplyInterestLib.applyInterestForToken(globalData.pairs, pairId);

        DataType.PairStatus storage pairStatus = globalData.pairs[pairId];

        Perp.updateRebalanceFeeGrowth(pairStatus, pairStatus.sqrtAssetStatus);

        {
            int256 deltaPositionBase;
            int256 deltaPositionQuote;

            (relocationOccurred, deltaPositionBase, deltaPositionQuote) =
                Perp.reallocate(pairStatus, pairStatus.sqrtAssetStatus);

            if (deltaPositionBase != 0) {
                globalData.initializeLock(pairId, settlementData.settlementContractAddress);

                ISettlement(settlementData.settlementContractAddress).predySettlementCallback(
                    settlementData.encodedData, deltaPositionBase
                );

                if (globalData.settle(true) + deltaPositionQuote < 0) {
                    revert IPredyPool.CurrencyNotSettled();
                }

                if (globalData.settle(false) + deltaPositionBase < 0) {
                    revert IPredyPool.CurrencyNotSettled();
                }

                delete globalData.lockData;
            }
        }

        if (relocationOccurred) {
            globalData.rebalanceFeeGrowthCache[PairLib.getRebalanceCacheId(
                pairId, pairStatus.sqrtAssetStatus.numRebalance
            )] = DataType.RebalanceFeeGrowthCache(
                pairStatus.sqrtAssetStatus.rebalanceFeeGrowthStable,
                pairStatus.sqrtAssetStatus.rebalanceFeeGrowthUnderlying
            );

            Perp.finalizeReallocation(pairStatus.sqrtAssetStatus);
        }
    }
}
