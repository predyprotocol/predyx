// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../interfaces/IPredyPool.sol";
import "../interfaces/IHooks.sol";

abstract contract BaseHookCallback is IHooks {
    IPredyPool _predyPool;

    mapping(uint256 pairId => address quoteTokenAddress) internal _quoteTokenMap;

    error CallerIsNotPredyPool();

    constructor(IPredyPool predyPool) {
        _predyPool = predyPool;
    }

    modifier onlyPredyPool() {
        if (msg.sender != address(_predyPool)) revert CallerIsNotPredyPool();
        _;
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external virtual;

    function updateQuoteTokenMap(uint256 pairId) external {
        if (_quoteTokenMap[pairId] == address(0)) {
            _quoteTokenMap[pairId] = _getQuoteTokenAddress(pairId);
        }
    }

    function _getQuoteTokenAddress(uint256 pairId) internal view returns (address) {
        Perp.PairStatus memory pairStatus = _predyPool.getPairStatus(pairId);

        return pairStatus.quotePool.token;
    }
}
