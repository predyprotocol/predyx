// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SpotMarket} from "../markets/spot/SpotMarket.sol";
import {SpotOrder} from "../markets/spot/SpotOrder.sol";
import {ISettlement} from "../interfaces/ISettlement.sol";
import {ISpotOrderValidator} from "../interfaces/IOrderValidator.sol";

/**
 * @notice Quoter contract for SpotMarket
 */
contract SpotMarketQuoter {
    SpotMarket spotMarket;

    constructor(SpotMarket _spotMarket) {
        spotMarket = _spotMarket;
    }

    function quoteExecuteOrder(SpotOrder memory order, SpotMarket.SettlementParams memory settlementParams)
        external
        returns (int256 quoteTokenAmount)
    {
        int256 baseTokenAmount = order.baseTokenAmount;

        try spotMarket.quoteSettlement(settlementParams, -baseTokenAmount) {}
        catch (bytes memory reason) {
            quoteTokenAmount = _parseRevertReason(reason);
        }

        if (order.validatorAddress != address(0)) {
            ISpotOrderValidator(order.validatorAddress).validate(order, baseTokenAmount, quoteTokenAmount, msg.sender);
        }
    }

    /// @notice Return the trade result of abi-encoded bytes.
    /// @param reason abi-encoded quoteTokenAmount
    function _parseRevertReason(bytes memory reason) private pure returns (int256) {
        if (reason.length != 32) {
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }

        return abi.decode(reason, (int256));
    }
}
