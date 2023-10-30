// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {OrderInfo, OrderInfoLib} from "./OrderInfoLib.sol";
import {IFillerMarket} from "../../interfaces/IFillerMarket.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {ResolvedOrder} from "./ResolvedOrder.sol";
import "../Constants.sol";

struct PerpOrder {
    OrderInfo info;
    uint256 positionId;
    uint64 pairId;
    address entryTokenAddress;
    int256 tradeAmount;
    int256 marginAmount;
    address validatorAddress;
    bytes validationData;
}

/// @notice helpers for handling perp order objects
library PerpOrderLib {
    using OrderInfoLib for OrderInfo;

    bytes internal constant PERP_ORDER_TYPE = abi.encodePacked(
        "PerpOrder(",
        "OrderInfo info,",
        "uint256 positionId,",
        "uint64 pairId,",
        "address entryTokenAddress,",
        "int256 tradeAmount,",
        "int256 marginAmount,",
        "address validatorAddress",
        "bytes validationData)"
    );

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    bytes internal constant ORDER_TYPE = abi.encodePacked(OrderInfoLib.ORDER_INFO_TYPE, PERP_ORDER_TYPE);
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
                order.info.hash(),
                order.positionId,
                order.pairId,
                order.entryTokenAddress,
                order.tradeAmount,
                order.marginAmount,
                order.validatorAddress,
                order.validationData
            )
        );
    }

    function resolve(PerpOrder memory perpOrder, bytes memory sig) internal pure returns (ResolvedOrder memory) {
        // perpOrder = abi.decode(order.order, (PerpOrder));

        uint256 amount = perpOrder.marginAmount > 0 ? uint256(perpOrder.marginAmount) : 0;

        return ResolvedOrder(perpOrder.info, perpOrder.entryTokenAddress, amount, hash(perpOrder), sig);
    }
}