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
    constructor() {}

    function quoteExecuteOrder(SpotOrder memory order, ISettlement.SettlementData memory settlementData)
        external
        returns (int256 quoteTokenAmount)
    {
        int256 baseTokenAmount = order.baseTokenAmount;

        try ISettlement(settlementData.settlementContractAddress).quoteSettlement(
            settlementData.encodedData, -baseTokenAmount
        ) {} catch (bytes memory reason) {
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
            if (reason.length < 68) revert("Unexpected error");
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }

        return abi.decode(reason, (int256));
    }
}