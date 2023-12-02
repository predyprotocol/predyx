// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Owned} from "@solmate/src/auth/Owned.sol";
import "./BaseHookCallback.sol";

abstract contract BaseMarket is BaseHookCallback, Owned {
    address public _whitelistFiller;

    mapping(uint256 pairId => address quoteTokenAddress) internal _quoteTokenMap;

    constructor(IPredyPool predyPool, address whitelistFiller) BaseHookCallback(predyPool) Owned(msg.sender) {
        _whitelistFiller = whitelistFiller;
    }

    /**
     * @notice Updates the whitelist filler address
     * @dev only owner can call this function
     */
    function updateWhitelistFiller(address newWhitelistFiller) external onlyOwner {
        _whitelistFiller = newWhitelistFiller;
    }

    /// @notice Registers quote token address for the pair
    function updateQuoteTokenMap(uint256 pairId) external {
        if (_quoteTokenMap[pairId] == address(0)) {
            _quoteTokenMap[pairId] = _getQuoteTokenAddress(pairId);
        }
    }

    /// @notice Checks if entryTokenAddress is registerd for the pair
    function validateQuoteTokenAddress(uint256 pairId, address entryTokenAddress) internal view {
        require(_quoteTokenMap[pairId] != address(0) && entryTokenAddress == _quoteTokenMap[pairId]);
    }

    function _getQuoteTokenAddress(uint256 pairId) internal view returns (address) {
        DataType.PairStatus memory pairStatus = _predyPool.getPairStatus(pairId);

        return pairStatus.quotePool.token;
    }
}
