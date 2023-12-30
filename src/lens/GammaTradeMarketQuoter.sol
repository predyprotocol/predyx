// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {GammaTradeMarket} from "../markets/gamma/GammaTradeMarket.sol";
import {GammaOrder} from "../markets/gamma/GammaOrder.sol";
import {ISettlement} from "../interfaces/ISettlement.sol";
import {IPredyPool} from "../interfaces/IPredyPool.sol";
import {SettlementCallbackLib} from "../base/SettlementCallbackLib.sol";

/**
 * @notice Quoter contract for GammaTradeMarket
 */
contract GammaTradeMarketQuoter {
    GammaTradeMarket public gammaTradeMarket;

    constructor(GammaTradeMarket _gammaTradeMarket) {
        gammaTradeMarket = _gammaTradeMarket;
    }

    function quoteExecuteOrder(GammaOrder memory order, SettlementCallbackLib.SettlementParams memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        try gammaTradeMarket.quoteExecuteOrder(order, settlementData) {}
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
