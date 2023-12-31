// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {PerpMarket} from "../markets/perp/PerpMarket.sol";
import {PerpOrder} from "../markets/perp/PerpOrder.sol";
import {ISettlement} from "../interfaces/ISettlement.sol";
import {IPredyPool} from "../interfaces/IPredyPool.sol";
import {IFillerMarket} from "../interfaces/IFillerMarket.sol";

/**
 * @notice Quoter contract for PerpMarket
 */
contract PerpMarketQuoter {
    PerpMarket public perpMarket;

    constructor(PerpMarket _perpMarket) {
        perpMarket = _perpMarket;
    }

    function quoteExecuteOrder(
        PerpOrder memory order,
        IFillerMarket.SettlementParams memory settlementParams,
        address filler
    ) external returns (IPredyPool.TradeResult memory tradeResult) {
        try perpMarket.quoteExecuteOrder(order, settlementParams, filler) {}
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
