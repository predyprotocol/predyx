// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {Constants} from "../Constants.sol";
import {DataType} from "../DataType.sol";
import {Perp} from "../Perp.sol";
import {GlobalDataLibrary} from "../../types/GlobalData.sol";
import {PositionCalculator} from "../PositionCalculator.sol";

library MarginLogic {
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;
    using SafeTransferLib for ERC20;

    event MarginUpdated(uint256 vaultId, int256 updateMarginAmount);

    function updateMargin(GlobalDataLibrary.GlobalData storage globalData, uint256 vaultId, int256 updateMarginAmount)
        external
    {
        DataType.Vault storage vault = globalData.vaults[vaultId];
        DataType.PairStatus memory pairStatus = globalData.pairs[vault.openPosition.pairId];

        // TODO: check vault and pair
        globalData.validateVaultId(vaultId);
        globalData.validate(vault.openPosition.pairId);

        vault.margin += updateMarginAmount;

        PositionCalculator.checkSafe(pairStatus, globalData.rebalanceFeeGrowthCache, vault);

        if (updateMarginAmount > 0) {
            ERC20(vault.marginId).safeTransferFrom(msg.sender, address(this), uint256(updateMarginAmount));
        } else if (updateMarginAmount < 0) {
            ERC20(vault.marginId).safeTransfer(vault.owner, uint256(-updateMarginAmount));
        }

        emit MarginUpdated(vaultId, updateMarginAmount);
    }
}
