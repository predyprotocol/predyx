// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../PerpMarket.sol";
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
        returns (PerpMarket.PerpTradeResult memory perpTradeResult)
    {
        try perpMarket.quoteExecuteOrder(order, settlementData, predyPoolQuoter) {}
        catch (bytes memory reason) {
            perpTradeResult = _parseRevertReasonAsTradeResult(reason);
        }
    }

    function quoteUserPosition(uint256 positionId) external returns (PerpMarket.UserPosition memory userPosition) {
        try perpMarket.quoteUserPosition(positionId) {}
        catch (bytes memory reason) {
            userPosition = _parseRevertReasonAsUserPosition(reason);
        }
    }

    /// @notice Return the trade result of abi-encoded bytes.
    /// @param reason abi-encoded tradeResult
    function _parseRevertReasonAsTradeResult(bytes memory reason)
        private
        pure
        returns (PerpMarket.PerpTradeResult memory perpTradeResult)
    {
        if (reason.length < 192) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (PerpMarket.PerpTradeResult));
        }
    }

    function _parseRevertReasonAsUserPosition(bytes memory reason)
        private
        pure
        returns (PerpMarket.UserPosition memory)
    {
        if (reason.length < 192) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (PerpMarket.UserPosition));
        }
    }
}
