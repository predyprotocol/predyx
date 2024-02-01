// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {PerpMarketV1} from "./PerpMarketV1.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {PerpOrder} from "./PerpOrder.sol";
import {OrderInfo} from "../../libraries/orders/OrderInfoLib.sol";

struct PerpOrderV2 {
    address trader;
    uint256 nonce;
    bytes32 deadlinePairIdLev;
    int256 tradeAmount;
    int256 marginAmount;
    address validatorAddress;
    bytes validationData;
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
        (uint64 deadline, uint64 pairId, uint8 leverage) = decodePerpOrderParams(orderV2.deadlinePairIdLev);

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

    function decodePerpOrderParams(bytes32 args)
        internal
        pure
        returns (uint64 deadline, uint64 pairId, uint8 leverage)
    {
        assembly {
            deadline := and(args, 0xFFFFFFFFFFFFFFFF)
            pairId := and(shr(64, args), 0xFFFFFFFFFFFFFFFF)
            leverage := and(shr(128, args), 0xFF)
        }
    }
}
