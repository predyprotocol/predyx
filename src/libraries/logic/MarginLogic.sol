// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {Constants} from "../Constants.sol";
import {DataType} from "../DataType.sol";
import {Perp} from "../Perp.sol";
import {GlobalDataLibrary} from "../../types/GlobalData.sol";
import {PositionCalculator} from "../PositionCalculator.sol";

library MarginLogic {
    function updateMargin(
        DataType.Vault storage vault,
        Perp.PairStatus memory pairStatus,
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) storage rebalanceFeeGrowthCache,
        int256 updateMarginAmount
    ) external {
        vault.margin += updateMarginAmount;

        PositionCalculator.checkSafe(pairStatus, rebalanceFeeGrowthCache, vault);
    }
}
