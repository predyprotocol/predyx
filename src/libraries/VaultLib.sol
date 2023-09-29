// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import "../interfaces/IPredyPool.sol";
import "../types/GlobalData.sol";

library VaultLib {
    error VaultAlreadyHasAnotherPair();

    error VaultAlreadyHasAnotherMarginId();

    error CallerIsNotVaultOwner();

    function getVault(GlobalDataLibrary.GlobalData storage globalData, uint256 vaultId)
        internal
        view
        returns (DataType.Vault storage vault)
    {
        vault = globalData.vaults[vaultId];

        // Ensure the caller is the owner of the existing vault
        if (vault.owner != msg.sender) {
            revert CallerIsNotVaultOwner();
        }
    }

    function createOrGetVault(GlobalDataLibrary.GlobalData storage globalData, uint256 vaultId, uint256 pairId)
        internal
        returns (DataType.Vault storage vault)
    {
        address marginId = globalData.pairs[pairId].marginId;

        if (vaultId == 0) {
            uint256 finalVaultId = globalData.vaultCount;

            // Initialize a new vault
            vault = globalData.vaults[finalVaultId];

            vault.id = finalVaultId;
            vault.owner = msg.sender;
            vault.recepient = msg.sender;
            vault.openPosition.pairId = pairId;
            vault.marginId = marginId;

            globalData.vaultCount++;
        } else {
            vault = globalData.vaults[vaultId];

            // Ensure the caller is the owner of the existing vault
            if (vault.owner != msg.sender) {
                revert CallerIsNotVaultOwner();
            }

            if (vault.marginId != marginId) {
                revert VaultAlreadyHasAnotherMarginId();
            }

            if (vault.openPosition.pairId != pairId) {
                revert VaultAlreadyHasAnotherPair();
            }
        }
    }
}
