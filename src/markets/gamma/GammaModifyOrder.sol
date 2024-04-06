// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {OrderInfo, OrderInfoLib} from "../../libraries/orders/OrderInfoLib.sol";
import {ResolvedOrder} from "../../libraries/orders/ResolvedOrder.sol";

struct GammaModifyOrder {
    OrderInfo info;
    uint64 pairId;
    uint64 slotId;
    uint64 expiration;
    uint256 lowerLimit;
    uint256 upperLimit;
    uint32 hedgeInterval;
    uint64 sqrtPriceTrigger;
    uint64 minSlippageTolerance;
    uint64 maxSlippageTolerance;
}

/// @notice helpers for handling general order objects
library GammaModifyOrderLib {
    using OrderInfoLib for OrderInfo;

    bytes internal constant GAMMA_MODIFY_ORDER_TYPE = abi.encodePacked(
        "GammaModifyOrder(",
        "OrderInfo info,",
        "uint64 pairId,",
        "uint64 slotId,",
        "uint64 expiration,",
        "uint256 lowerLimit,",
        "uint256 upperLimit,",
        "uint32 hedgeInterval,",
        "uint64 sqrtPriceTrigger,",
        "uint64 minSlippageTolerance,",
        "uint64 maxSlippageTolerance)"
    );

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    bytes internal constant ORDER_TYPE = abi.encodePacked(GAMMA_MODIFY_ORDER_TYPE, OrderInfoLib.ORDER_INFO_TYPE);
    bytes32 internal constant GAMMA_MODIFY_ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    string internal constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("GammaModifyOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(GammaModifyOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                GAMMA_MODIFY_ORDER_TYPE_HASH,
                order.info.hash(),
                order.pairId,
                order.slotId,
                order.expiration,
                order.lowerLimit,
                order.upperLimit,
                order.hedgeInterval,
                order.sqrtPriceTrigger,
                order.minSlippageTolerance,
                order.maxSlippageTolerance
            )
        );
    }

    function resolve(GammaModifyOrder memory gammaOrder, bytes memory sig)
        internal
        pure
        returns (ResolvedOrder memory)
    {
        return ResolvedOrder(gammaOrder.info, address(0), 0, hash(gammaOrder), sig);
    }
}
