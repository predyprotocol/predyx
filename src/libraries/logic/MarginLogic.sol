// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {Constants} from "../Constants.sol";
import {DataType} from "../DataType.sol";
import {Perp} from "../Perp.sol";
import {GlobalDataLibrary} from "../../types/GlobalData.sol";
import {PositionCalculator} from "../PositionCalculator.sol";

library MarginLogic {
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;

    function updateMargin(GlobalDataLibrary.GlobalData storage globalData, uint256 vaultId, int256 updateMarginAmount)
        external
    {
        DataType.Vault storage vault = globalData.vaults[vaultId];
        Perp.PairStatus memory pairStatus = globalData.pairs[vault.openPosition.pairId];

        // TODO: check vault and pair
        globalData.validateVaultId(vaultId);
        globalData.validate(vault.openPosition.pairId);

        vault.margin += updateMarginAmount;

        PositionCalculator.checkSafe(pairStatus, globalData.rebalanceFeeGrowthCache, vault);

        if (updateMarginAmount > 0) {
            IERC20(vault.marginId).transferFrom(msg.sender, address(this), uint256(updateMarginAmount));
        } else if (updateMarginAmount < 0) {
            TransferHelper.safeTransfer(vault.marginId, vault.owner, uint256(-updateMarginAmount));
        }
    }
}
