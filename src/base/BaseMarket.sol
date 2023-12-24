// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Owned} from "@solmate/src/auth/Owned.sol";
import "./BaseHookCallback.sol";
import {PredyPoolQuoter} from "../lens/PredyPoolQuoter.sol";
import "../interfaces/IFillerMarket.sol";

abstract contract BaseMarket is IFillerMarket, BaseHookCallback, Owned {
    address public whitelistFiller;

    PredyPoolQuoter internal immutable _quoter;

    mapping(uint256 pairId => address quoteTokenAddress) internal _quoteTokenMap;

    constructor(IPredyPool predyPool, address _whitelistFiller, address quoterAddress)
        BaseHookCallback(predyPool)
        Owned(msg.sender)
    {
        whitelistFiller = _whitelistFiller;

        _quoter = PredyPoolQuoter(quoterAddress);
    }

    /**
     * @notice Updates the whitelist filler address
     * @dev only owner can call this function
     */
    function updateWhitelistFiller(address newWhitelistFiller) external onlyOwner {
        whitelistFiller = newWhitelistFiller;
    }

    /// @notice Registers quote token address for the pair
    function updateQuoteTokenMap(uint256 pairId) external {
        if (_quoteTokenMap[pairId] == address(0)) {
            _quoteTokenMap[pairId] = _getQuoteTokenAddress(pairId);
        }
    }

    /// @notice Checks if entryTokenAddress is registerd for the pair
    function _validateQuoteTokenAddress(uint256 pairId, address entryTokenAddress) internal view {
        require(_quoteTokenMap[pairId] != address(0) && entryTokenAddress == _quoteTokenMap[pairId]);
    }

    function _getQuoteTokenAddress(uint256 pairId) internal view returns (address) {
        DataType.PairStatus memory pairStatus = _predyPool.getPairStatus(pairId);

        return pairStatus.quotePool.token;
    }

    function _revertTradeResult(IPredyPool.TradeResult memory tradeResult) internal pure {
        bytes memory data = abi.encode(tradeResult);

        assembly {
            revert(add(32, data), mload(data))
        }
    }
}
