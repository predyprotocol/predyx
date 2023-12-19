// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {OrderInfo, OrderInfoLib} from "../../libraries/orders/OrderInfoLib.sol";
import {ResolvedOrder} from "../../libraries/orders/ResolvedOrder.sol";

struct PredictCloseOrder {
    OrderInfo info;
    uint256 positionId;
    address validatorAddress;
    bytes validationData;
}

/// @notice helpers for handling predict order objects
library PredictCloseOrderLib {
    using OrderInfoLib for OrderInfo;

    bytes internal constant PREDICT_CLOSE_ORDER_TYPE = abi.encodePacked(
        "PredictCloseOrder(",
        "OrderInfo info,",
        "uint256 positionId,",
        "address validatorAddress,",
        "bytes validationData)"
    );

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    bytes internal constant ORDER_TYPE = abi.encodePacked(PREDICT_CLOSE_ORDER_TYPE, OrderInfoLib.ORDER_INFO_TYPE);
    bytes32 internal constant PREDICT_ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    string internal constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE = string(
        abi.encodePacked(
            "PredictCloseOrder witness)", OrderInfoLib.ORDER_INFO_TYPE, PREDICT_CLOSE_ORDER_TYPE, TOKEN_PERMISSIONS_TYPE
        )
    );

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(PredictCloseOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                PREDICT_ORDER_TYPE_HASH,
                order.info.hash(),
                order.positionId,
                order.validatorAddress,
                keccak256(order.validationData)
            )
        );
    }

    function resolve(PredictCloseOrder memory predictOrder, bytes memory sig)
        internal
        pure
        returns (ResolvedOrder memory)
    {
        return ResolvedOrder(predictOrder.info, address(0), 0, hash(predictOrder), sig);
    }
}
