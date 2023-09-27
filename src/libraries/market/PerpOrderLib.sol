// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {OrderInfo, OrderInfoLib} from "./OrderInfoLib.sol";
import {IFillerMarket} from "../../interfaces/IFillerMarket.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {ResolvedOrder} from "./ResolvedOrder.sol";
import "../Constants.sol";

struct PerpOrder {
    OrderInfo info;
    uint64 positionId;
    uint64 pairId;
    int256 tradeAmount;
    uint256 triggerPrice;
    uint256 limitPrice;
    int256 marginAmount;
    uint256 marginRatio;
}

/// @notice helpers for handling perp order objects
library PerpOrderLib {
    using OrderInfoLib for OrderInfo;

    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    error TriggerNotMatched();

    bytes internal constant PERP_ORDER_TYPE = abi.encodePacked(
        "PerpOrder(",
        "uint256 positionId,",
        "uint256 pairId,",
        "int256 tradeAmount,",
        "uint256 triggerPrice,",
        "uint256 limitPrice,",
        "int256 marginAmount,",
        "uint256 marginRatio)"
    );

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    bytes internal constant ORDER_TYPE = abi.encodePacked(PERP_ORDER_TYPE, OrderInfoLib.ORDER_INFO_TYPE);
    bytes32 internal constant PERP_ORDER_TYPE_HASH = keccak256(PERP_ORDER_TYPE);

    string internal constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("PerpOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(PerpOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                PERP_ORDER_TYPE_HASH,
                order.positionId,
                order.pairId,
                order.tradeAmount,
                order.triggerPrice,
                order.limitPrice,
                order.marginAmount,
                order.marginRatio
            )
        );
    }

    function resolve(IFillerMarket.SignedOrder memory order, address token)
        internal
        pure
        returns (PerpOrder memory perpOrder, ResolvedOrder memory)
    {
        perpOrder = abi.decode(order.order, (PerpOrder));

        uint256 amount = perpOrder.marginAmount > 0 ? uint256(perpOrder.marginAmount) : 0;

        return (perpOrder, ResolvedOrder(perpOrder.info, token, amount, hash(perpOrder), order.sig));
    }

    function validateGeneralOrder(PerpOrder memory perpOrder, IPredyPool.TradeResult memory tradeResult)
        internal
        pure
    {
        if (perpOrder.triggerPrice > 0) {
            uint256 twap = (tradeResult.sqrtTwap * tradeResult.sqrtTwap) >> Constants.RESOLUTION;

            if (perpOrder.tradeAmount > 0 && perpOrder.triggerPrice < twap) {
                revert TriggerNotMatched();
            }
            if (perpOrder.tradeAmount < 0 && perpOrder.triggerPrice > twap) {
                revert TriggerNotMatched();
            }
        }

        if (perpOrder.limitPrice > 0) {
            if (perpOrder.tradeAmount > 0 && perpOrder.limitPrice < uint256(-tradeResult.payoff.perpEntryUpdate)) {
                revert PriceGreaterThanLimit();
            }

            if (perpOrder.tradeAmount < 0 && perpOrder.limitPrice > uint256(tradeResult.payoff.perpEntryUpdate)) {
                revert PriceLessThanLimit();
            }
        }
    }
}
