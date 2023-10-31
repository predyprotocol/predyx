// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../interfaces/IFillerMarket.sol";
import "../interfaces/ISettlement.sol";
import "../interfaces/ILendingPool.sol";

contract AavePerp is IFillerMarket, ILendingPool {
    struct PerpTradeResult {
        int256 entryUpdate;
        int256 payoff;
    }

    function executeOrder(SignedOrder memory order, ISettlement.SettlementData memory settlementData)
        external
        returns (PerpTradeResult memory perpTradeResult)
    {}

    /**
     * @notice Takes tokens
     * @dev Only locker can call this function
     */
    function take(bool isQuoteAsset, address to, uint256 amount) external {}
}
