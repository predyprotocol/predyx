// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {OrderInfo, OrderInfoLib} from "../../libraries/orders/OrderInfoLib.sol";
import {ResolvedOrder} from "../../libraries/orders/ResolvedOrder.sol";

struct PredictOrder {
    OrderInfo info;
    uint64 pairId;
    uint64 duration;
    address entryTokenAddress;
    int256 tradeAmount;
    int256 tradeAmountSqrt;
    uint256 marginAmount;
    address validatorAddress;
    bytes validationData;
}

/// @notice helpers for handling predict order objects
library PredictOrderLib {
    using OrderInfoLib for OrderInfo;

    bytes internal constant PREDICT_ORDER_TYPE = abi.encodePacked(
        "PredictOrder(",
        "OrderInfo info,",
        "uint64 pairId,",
        "uint64 duration,",
        "address entryTokenAddress,",
        "int256 tradeAmount,",
        "int256 tradeAmountSqrt,",
        "uint256 marginAmount,",
        "address validatorAddress",
        "bytes validationData)"
    );

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    bytes internal constant ORDER_TYPE = abi.encodePacked(PREDICT_ORDER_TYPE, OrderInfoLib.ORDER_INFO_TYPE);
    bytes32 internal constant PREDICT_ORDER_TYPE_HASH = keccak256(PREDICT_ORDER_TYPE);

    string internal constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("PredictOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(PredictOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                PREDICT_ORDER_TYPE_HASH,
                order.info.hash(),
                order.pairId,
                order.duration,
                order.entryTokenAddress,
                order.tradeAmount,
                order.tradeAmountSqrt,
                order.marginAmount,
                order.validatorAddress,
                order.validationData
            )
        );
    }

    function resolve(PredictOrder memory predictOrder, bytes memory sig) internal pure returns (ResolvedOrder memory) {
        return ResolvedOrder(
            predictOrder.info, predictOrder.entryTokenAddress, predictOrder.marginAmount, hash(predictOrder), sig
        );
    }
}
