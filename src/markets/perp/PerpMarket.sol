// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {PerpMarketV1} from "./PerpMarketV1.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {PerpOrder} from "./PerpOrder.sol";
import {PerpOrderV3} from "./PerpOrderV3.sol";
import {OrderInfo} from "../../libraries/orders/OrderInfoLib.sol";
import {L2Decoder} from "../L2Decoder.sol";
import {Bps} from "../../libraries/math/Bps.sol";
import {DataType} from "../../libraries/DataType.sol";

struct PerpOrderV2 {
    address trader;
    uint256 nonce;
    bytes32 deadlinePairIdLev;
    int256 tradeAmount;
    int256 marginAmount;
    address validatorAddress;
    bytes validationData;
}

struct PerpOrderV3L2 {
    address trader;
    uint256 nonce;
    int256 tradeAmount;
    uint256 marginAmount;
    uint256 limitPrice;
    uint256 stopPrice;
    bytes32 data1;
    bytes auctionData;
}

/**
 * @notice Perp market contract for Layer2.
 * Optimizing calldata size in this contract since L2 calldata is relatively expensive.
 */
contract PerpMarket is PerpMarketV1 {
    function executeOrderV2(PerpOrderV2 memory orderV2, bytes memory sig, SettlementParams memory settlementParams)
        external
        nonReentrant
        returns (IPredyPool.TradeResult memory)
    {
        (uint64 deadline, uint64 pairId, uint8 leverage) = L2Decoder.decodePerpOrderParams(orderV2.deadlinePairIdLev);

        UserPosition memory userPosition = userPositions[orderV2.trader][pairId];

        PerpOrder memory order = PerpOrder({
            info: OrderInfo(address(this), orderV2.trader, orderV2.nonce, deadline),
            pairId: pairId,
            entryTokenAddress: _quoteTokenMap[pairId],
            tradeAmount: orderV2.tradeAmount,
            marginAmount: orderV2.marginAmount,
            leverage: leverage,
            takeProfitPrice: userPosition.takeProfitPrice,
            stopLossPrice: userPosition.stopLossPrice,
            slippageTolerance: userPosition.slippageTolerance,
            validatorAddress: orderV2.validatorAddress,
            validationData: orderV2.validationData
        });

        return _executeOrder(order, sig, settlementParams);
    }

    function executeOrderV3L2(
        PerpOrderV3L2 memory compressedOrder,
        bytes memory sig,
        SettlementParamsV2 memory settlementParams
    ) external nonReentrant returns (IPredyPool.TradeResult memory) {
        (uint64 deadline, uint64 pairId, uint8 leverage, bool reduceOnly, bool closePosition) =
            L2Decoder.decodePerpOrderV3Params(compressedOrder.data1);

        PerpOrderV3 memory order = PerpOrderV3({
            info: OrderInfo(address(this), compressedOrder.trader, compressedOrder.nonce, deadline),
            pairId: pairId,
            entryTokenAddress: _quoteTokenMap[pairId],
            tradeAmount: compressedOrder.tradeAmount,
            marginAmount: compressedOrder.marginAmount,
            limitPrice: compressedOrder.limitPrice,
            stopPrice: compressedOrder.stopPrice,
            leverage: leverage,
            reduceOnly: reduceOnly,
            closePosition: closePosition,
            auctionData: compressedOrder.auctionData
        });

        return _executeOrderV3(order, sig, settlementParams);
    }
}
