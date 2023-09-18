// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {OrderInfo, OrderInfoLib} from "./OrderInfoLib.sol";
import {IFillerMarket} from "../../interfaces/IFillerMarket.sol";
import {ResolvedOrder} from "./ResolvedOrder.sol";

struct MarketOrder {
    OrderInfo info;
    uint256 positionId;
    uint256 pairId;
    int256 tradeAmount;
    int256 tradeAmountSqrt;
    uint256 limitPrice;
    uint256 limitPriceSqrt;
    int256 marginAmount;
    uint256 marginRatio;
}

/// @notice helpers for handling dutch order objects
library MarketOrderLib {
    using OrderInfoLib for OrderInfo;

    bytes internal constant MARKET_ORDER_TYPE = abi.encodePacked(
        "MarketOrder(",
        "uint256 positionId,",
        "uint256 pairId,",
        "int256 tradeAmount,",
        "int256 tradeAmountSqrt,",
        "uint256 limitPrice,",
        "uint256 limitPriceSqrt,",
        "int256 marginAmount,",
        "uint256 marginRatio)"
    );

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    bytes internal constant ORDER_TYPE = abi.encodePacked(MARKET_ORDER_TYPE, OrderInfoLib.ORDER_INFO_TYPE);
    bytes32 internal constant MARKET_ORDER_TYPE_HASH = keccak256(MARKET_ORDER_TYPE);

    string internal constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("MarketOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(MarketOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                MARKET_ORDER_TYPE_HASH,
                order.positionId,
                order.pairId,
                order.tradeAmount,
                order.tradeAmountSqrt,
                order.limitPrice,
                order.limitPriceSqrt,
                order.marginAmount,
                order.marginRatio
            )
        );
    }

    function resolve(IFillerMarket.SignedOrder memory order, address token)
        internal
        pure
        returns (MarketOrder memory marketOrder, ResolvedOrder memory)
    {
        marketOrder = abi.decode(order.order, (MarketOrder));

        uint256 amount = marketOrder.marginAmount > 0 ? uint256(marketOrder.marginAmount) : 0;

        return (marketOrder, ResolvedOrder(marketOrder.info, token, amount, hash(marketOrder), order.sig));
    }
}
