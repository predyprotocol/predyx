// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {BaseHookCallbackUpgradable} from "./BaseHookCallbackUpgradable.sol";
import {PredyPoolQuoter} from "../lens/PredyPoolQuoter.sol";
import {IPredyPool} from "../interfaces/IPredyPool.sol";
import {DataType} from "../libraries/DataType.sol";
import "../interfaces/IFillerMarket.sol";

abstract contract BaseMarketUpgradable is IFillerMarket, BaseHookCallbackUpgradable {
    address public whitelistFiller;

    PredyPoolQuoter internal _quoter;

    mapping(uint256 pairId => address quoteTokenAddress) internal _quoteTokenMap;

    modifier onlyFiller() {
        if (msg.sender != whitelistFiller) revert CallerIsNotFiller();
        _;
    }

    constructor() {}

    function __BaseMarket_init(IPredyPool predyPool, address _whitelistFiller, address quoterAddress)
        internal
        onlyInitializing
    {
        __BaseHookCallback_init(predyPool);

        whitelistFiller = _whitelistFiller;

        _quoter = PredyPoolQuoter(quoterAddress);
    }

    /**
     * @notice Updates the whitelist filler address
     * @dev only owner can call this function
     */
    function updateWhitelistFiller(address newWhitelistFiller) external onlyFiller {
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