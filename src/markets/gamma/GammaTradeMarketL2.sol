// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {GammaTradeMarket} from "./GammaTradeMarket.sol";
import {OrderInfo} from "../../libraries/orders/OrderInfoLib.sol";
import {GammaOrder, GammaOrderLib, GammaModifyInfo} from "./GammaOrder.sol";
import {L2GammaDecoder} from "./L2GammaDecoder.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";

struct GammaOrderL2 {
    address trader;
    uint256 nonce;
    uint256 deadline;
    uint256 positionId;
    int256 quantity;
    int256 quantitySqrt;
    int256 marginAmount;
    bool closePosition;
    int256 limitValue;
    uint8 leverage;
    bytes32 param;
    uint256 lowerLimit;
    uint256 upperLimit;
}

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
    // execute trade
    function executeTradeL2(GammaOrderL2 memory order, bytes memory sig, SettlementParamsV3 memory settlementParams)
        external
        nonReentrant
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        GammaModifyInfo memory modifyInfo =
            L2GammaDecoder.decodeGammaModifyInfo(order.param, order.lowerLimit, order.upperLimit);

        uint64 pairId = userPositions[order.positionId].pairId;

        return _executeTrade(
            GammaOrder(
                OrderInfo(address(this), order.trader, order.nonce, order.deadline),
                pairId,
                order.positionId,
                _quoteTokenMap[pairId],
                order.quantity,
                order.quantitySqrt,
                order.marginAmount,
                order.closePosition,
                order.limitValue,
                order.leverage,
                modifyInfo
            ),
            sig,
            settlementParams
        );
    }

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
