// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {PerpMarket} from "../markets/perp/PerpMarket.sol";
import {PerpOrder} from "../markets/perp/PerpOrder.sol";
import "./PredyPoolQuoter.sol";

/**
 * @notice Quoter contract for PerpMarket
 */
contract PerpMarketQuoter {
    PerpMarket public perpMarket;
    PredyPoolQuoter public predyPoolQuoter;

    constructor(PerpMarket _perpMarket, PredyPoolQuoter _predyPoolQuoter) {
        perpMarket = _perpMarket;
        predyPoolQuoter = _predyPoolQuoter;
    }

    function quoteExecuteOrder(PerpOrder memory order, ISettlement.SettlementData memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        try perpMarket.quoteExecuteOrder(order, settlementData, predyPoolQuoter) {}
        catch (bytes memory reason) {
            tradeResult = _parseRevertReason(reason);
        }
    }

    /// @notice Return the trade result of abi-encoded bytes.
    /// @param reason abi-encoded tradeResult
    function _parseRevertReason(bytes memory reason) private pure returns (IPredyPool.TradeResult memory tradeResult) {
        if (reason.length < 192) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (IPredyPool.TradeResult));
        }
    }
}
