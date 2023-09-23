// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "../Perp.sol";
import "../PairLib.sol";
import "../ApplyInterestLib.sol";
import "../../types/GlobalData.sol";
import "forge-std/console2.sol";

library ReallocationLogic {
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;

    function reallocate(
        GlobalDataLibrary.GlobalData storage globalData,
        uint256 pairId,
        IHooks.SettlementData memory settlementData
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

            IHooks(settlementData.settlementContractAddress).predySettlementCallback(
                settlementData.encodedData, deltaPositionBase
            );
            int256 a = globalData.settle(true) + deltaPositionQuote;
            int256 b = globalData.settle(false) + deltaPositionBase;

            console2.log(a);
            console2.log(b);

            if (a < 0) {
                revert IPredyPool.CurrencyNotSettled();
            }

            if (b < 0) {
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
