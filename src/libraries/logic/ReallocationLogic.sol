// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "../Perp.sol";
import "../PairLib.sol";
import "../ApplyInterestLib.sol";
import "../../types/GlobalData.sol";

library ReallocationLogic {
    function reallocate(GlobalDataLibrary.GlobalData storage globalData, uint256 pairId)
        external
        returns (bool reallocationHappened, int256 profit)
    {
        // Checks the pair exists
        // PairLib.validatePairId(globalData, pairId);

        // Updates interest rate related to the pair
        ApplyInterestLib.applyInterestForToken(globalData.pairs, pairId);

        Perp.PairStatus storage pairStatus = globalData.pairs[pairId];

        Perp.updateRebalanceFeeGrowth(pairStatus, pairStatus.sqrtAssetStatus);

        (reallocationHappened, profit) = Perp.reallocate(pairStatus, pairStatus.sqrtAssetStatus, false);

        if (reallocationHappened) {
            globalData.rebalanceFeeGrowthCache[PairLib.getRebalanceCacheId(
                pairId, pairStatus.sqrtAssetStatus.numRebalance
            )] = DataType.RebalanceFeeGrowthCache(
                pairStatus.sqrtAssetStatus.rebalanceFeeGrowthStable,
                pairStatus.sqrtAssetStatus.rebalanceFeeGrowthUnderlying
            );

            Perp.finalizeReallocation(pairStatus.sqrtAssetStatus);
        }

        if (profit < 0) {
            address token;

            if (pairStatus.isMarginZero) {
                token = pairStatus.basePool.token;
            } else {
                token = pairStatus.quotePool.token;
            }

            TransferHelper.safeTransferFrom(token, msg.sender, address(this), uint256(-profit));
        }
    }
}
