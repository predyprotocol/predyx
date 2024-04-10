// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {GammaTradeMarket} from "./GammaTradeMarket.sol";
import {OrderInfo} from "../../libraries/orders/OrderInfoLib.sol";
import {GammaOrder, GammaOrderLib, GammaModifyInfo} from "./GammaOrder.sol";
import {L2GammaDecoder} from "./L2GammaDecoder.sol";

struct GammaModifyOrderL2 {
    address trader;
    uint256 nonce;
    uint256 deadline;
    uint256 positionId;
    bytes32 param;
    uint256 lowerLimit;
    uint256 upperLimit;
}

/**
 * @notice Gamma trade market contract for Layer2.
 * Optimizing calldata size in this contract since L2 calldata is relatively expensive.
 */
contract GammaTradeMarketL2 is GammaTradeMarket {
    // modify position (hedge or close)
    function modifyAutoHedgeAndClose(GammaModifyOrderL2 memory order, bytes memory sig) external {
        GammaModifyInfo memory modifyInfo =
            L2GammaDecoder.decodeGammaModifyInfo(order.param, order.lowerLimit, order.upperLimit);

        uint64 pairId = userPositions[order.positionId].pairId;

        _modifyAutoHedgeAndClose(
            GammaOrder(
                OrderInfo(address(this), order.trader, order.nonce, order.deadline),
                pairId,
                order.positionId,
                _quoteTokenMap[pairId],
                0,
                0,
                0,
                false,
                0,
                0,
                modifyInfo
            ),
            sig
        );
    }
}
