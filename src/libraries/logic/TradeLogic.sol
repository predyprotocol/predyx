// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "../../interfaces/IPredyPool.sol";
import "../../types/GlobalData.sol";
import "../../interfaces/IPredyPool.sol";

library TradeLogic {
    function trade(
        GlobalDataLibrary.GlobalData storage globalData,
        uint256 pairId,
        IPredyPool.TradeParams memory tradeParams,
        bytes memory settlementData
    ) external 
            returns (IPredyPool.TradeResult memory tradeResult)
    {
        Perp.PairStatus storage pairStatus = globalData.pairs[pairId];

        Perp.updateRebalanceFeeGrowth(pairStatus, pairStatus.sqrtAssetStatus);

        // pre trade

        // swap

        // post trade

        // check vault is safe
    }
}
