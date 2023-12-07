// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {PredictMarket} from "../markets/predict/PredictMarket.sol";
import {PredictOrder} from "../markets/predict/PredictOrder.sol";
import "./PredyPoolQuoter.sol";

/**
 * @notice Quoter contract for PredictMarket
 */
contract PredictMarketQuoter {
    PredictMarket public predictMarket;
    PredyPoolQuoter public predyPoolQuoter;

    constructor(PredictMarket _perpMarket, PredyPoolQuoter _predyPoolQuoter) {
        predictMarket = _perpMarket;
        predyPoolQuoter = _predyPoolQuoter;
    }

    function quoteExecuteOrder(PredictOrder memory order, ISettlement.SettlementData memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        try predictMarket.quoteExecuteOrder(order, settlementData, predyPoolQuoter) {}
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
