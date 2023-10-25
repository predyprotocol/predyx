// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {Constants} from "../Constants.sol";
import {DataType} from "../DataType.sol";
import {Perp} from "../Perp.sol";
import {ApplyInterestLib} from "../ApplyInterestLib.sol";
import {GlobalDataLibrary} from "../../types/GlobalData.sol";
import {PositionCalculator} from "../PositionCalculator.sol";

library ReaderLogic {
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;

    function getPairStatus(GlobalDataLibrary.GlobalData storage globalData, uint256 pairId) external {
        ApplyInterestLib.applyInterestForToken(globalData.pairs, pairId);

        Perp.PairStatus memory pairStatus = globalData.pairs[pairId];

        revertPairStatus(pairStatus);
    }

    function getVaultStatus(GlobalDataLibrary.GlobalData storage globalData, uint256 vaultId) external {
        uint256 pairId = globalData.vaults[vaultId].openPosition.pairId;

        ApplyInterestLib.applyInterestForToken(globalData.pairs, pairId);

        (int256 minMargin, int256 vaultValue,,) = PositionCalculator.calculateMinDeposit(
            globalData.pairs[pairId], globalData.rebalanceFeeGrowthCache, globalData.vaults[vaultId]
        );

        revertVaultStatus(IPredyPool.VaultStatus(vaultId, vaultValue, minMargin));
    }

    function getPositionWithUnrealizedFee(GlobalDataLibrary.GlobalData storage globalData, uint256 vaultId)
        external
        view
        returns (PositionCalculator.PositionParams memory positionParams)
    {
        uint256 pairId = globalData.vaults[vaultId].openPosition.pairId;

        return PositionCalculator.getPositionWithUnrealizedFee(
            globalData.pairs[pairId], globalData.rebalanceFeeGrowthCache, globalData.vaults[vaultId].openPosition
        );
    }

    function revertPairStatus(Perp.PairStatus memory pairStatus) internal pure {
        bytes memory data = abi.encode(pairStatus);

        assembly {
            revert(add(32, data), mload(data))
        }
    }

    function revertVaultStatus(IPredyPool.VaultStatus memory vaultStatus) internal pure {
        bytes memory data = abi.encode(vaultStatus);

        assembly {
            revert(add(32, data), mload(data))
        }
    }
}
