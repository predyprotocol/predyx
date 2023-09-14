// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

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

    function validate(GlobalDataLibrary.GlobalData storage globalData, uint256 pairId) internal view {
        if (pairId <= 0 || globalData.pairsCount <= pairId) revert IPredyPool.InvalidPairId();
    }

    function initializeLock(GlobalDataLibrary.GlobalData storage globalData, uint256 pairId, address caller, int256 baseDelta) internal {
        globalData.lockData.quoteReserve = IERC20(globalData.pairs[pairId].quotePool.token).balanceOf(address(this));
        globalData.lockData.baseReserve = IERC20(globalData.pairs[pairId].basePool.token).balanceOf(address(this));
        globalData.lockData.locker = caller;
        globalData.lockData.pairId = pairId;
        globalData.lockData.baseDelta = baseDelta;        
    }

    function take(GlobalDataLibrary.GlobalData storage globalData, address currency, address to, uint256 amount) internal {
        LockDataLibrary.LockData storage lockData = globalData.lockData;
        Perp.PairStatus memory pairStatus = globalData.pairs[lockData.pairId];

        if(currency == pairStatus.quotePool.token) {
            lockData.quoteDelta -= int256(amount);
            IERC20(currency).transfer(to, amount);
        } else if(currency == pairStatus.basePool.token) {
            lockData.baseDelta -= int256(amount);
            IERC20(currency).transfer(to, amount);
        }
    }

    function settle(GlobalDataLibrary.GlobalData storage globalData, bool isQuoteAsset) internal returns (uint256 paid) {
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

        paid = reserveAfter - reservesBefore;

        if (isQuoteAsset) {
            globalData.lockData.quoteDelta += int256(paid);
        } else {
            globalData.lockData.baseDelta += int256(paid);
        }
    }

}
