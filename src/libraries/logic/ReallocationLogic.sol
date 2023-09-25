// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import "../Perp.sol";
import "../PairLib.sol";
import "../ApplyInterestLib.sol";
import "../../types/GlobalData.sol";

library ReallocationLogic {
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;

    function reallocate(
        GlobalDataLibrary.GlobalData storage globalData,
        uint256 pairId,
        ISettlement.SettlementData memory settlementData
    ) external returns (bool relocationOccurred) {
        // Checks the pair exists
        // PairLib.validatePairId(globalData, pairId);

        // Updates interest rate related to the pair
        ApplyInterestLib.applyInterestForToken(globalData.pairs, pairId);

        Perp.PairStatus storage pairStatus = globalData.pairs[pairId];

        Perp.updateRebalanceFeeGrowth(pairStatus, pairStatus.sqrtAssetStatus);

        {
            int256 deltaPositionBase;
            int256 deltaPositionQuote;

            (relocationOccurred, deltaPositionBase, deltaPositionQuote) =
                Perp.reallocate(pairStatus, pairStatus.sqrtAssetStatus);

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
