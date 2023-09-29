// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IPredyPool.sol";
import "../libraries/DataType.sol";
import "./LockData.sol";

library GlobalDataLibrary {
    struct GlobalData {
        uint256 pairsCount;
        uint256 vaultCount;
        address uniswapFactory;
        mapping(uint256 => Perp.PairStatus) pairs;
        mapping(uint256 => DataType.RebalanceFeeGrowthCache) rebalanceFeeGrowthCache;
        mapping(uint256 => DataType.Vault) vaults;
        LockDataLibrary.LockData lockData;
    }

    function validateVaultId(GlobalDataLibrary.GlobalData storage globalData, uint256 vaultId) internal view {
        if (vaultId <= 0 || globalData.vaultCount <= vaultId) revert IPredyPool.InvalidPairId();
    }

    function validate(GlobalDataLibrary.GlobalData storage globalData, uint256 pairId) internal view {
        if (pairId <= 0 || globalData.pairsCount <= pairId) revert IPredyPool.InvalidPairId();
    }

    function initializeLock(GlobalDataLibrary.GlobalData storage globalData, uint256 pairId, address caller) internal {
        if (globalData.lockData.locker != address(0)) {
            revert IPredyPool.LockedBy(globalData.lockData.locker);
        }

        globalData.lockData.quoteReserve = IERC20(globalData.pairs[pairId].quotePool.token).balanceOf(address(this));
        globalData.lockData.baseReserve = IERC20(globalData.pairs[pairId].basePool.token).balanceOf(address(this));
        globalData.lockData.locker = caller;
        globalData.lockData.pairId = pairId;
    }

    function take(GlobalDataLibrary.GlobalData storage globalData, bool isQuoteAsset, address to, uint256 amount)
        internal
    {
        Perp.PairStatus memory pairStatus = globalData.pairs[globalData.lockData.pairId];

        address currency;

        if (isQuoteAsset) {
            currency = pairStatus.quotePool.token;
        } else {
            currency = pairStatus.basePool.token;
        }

        IERC20(currency).transfer(to, amount);
    }

    function settle(GlobalDataLibrary.GlobalData storage globalData, bool isQuoteAsset)
        internal
        returns (int256 paid)
    {
        address currency;
        uint256 reservesBefore;

        if (isQuoteAsset) {
            currency = globalData.pairs[globalData.lockData.pairId].quotePool.token;
            reservesBefore = globalData.lockData.quoteReserve;
        } else {
            currency = globalData.pairs[globalData.lockData.pairId].basePool.token;
            reservesBefore = globalData.lockData.baseReserve;
        }

        uint256 reserveAfter = IERC20(currency).balanceOf(address(this));

        if (isQuoteAsset) {
            globalData.lockData.quoteReserve = reserveAfter;
        } else {
            globalData.lockData.baseReserve = reserveAfter;
        }

        paid = int256(reserveAfter) - int256(reservesBefore);
    }
}
