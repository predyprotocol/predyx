// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {OrderInfo, OrderInfoLib} from "../../libraries/orders/OrderInfoLib.sol";
import {IFillerMarket} from "../../interfaces/IFillerMarket.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {ResolvedOrder} from "../../libraries/orders/ResolvedOrder.sol";

struct GammaModifyInfo {
    uint64 expiration;
    uint256 lowerLimit;
    uint256 upperLimit;
    uint32 hedgeInterval;
    uint64 sqrtPriceTrigger;
    uint64 minSlippageTolerance;
    uint64 maxSlippageTolerance;
}

library GammaModifyInfoLib {
    bytes internal constant GAMMA_MODIFY_INFO_TYPE = abi.encodePacked(
        "GammaModifyInfo(",
        "uint64 expiration,",
        "uint256 lowerLimit,",
        "uint256 upperLimit,",
        "uint32 hedgeInterval,",
        "uint64 sqrtPriceTrigger,",
        "uint64 minSlippageTolerance,",
        "uint64 maxSlippageTolerance)"
    );

    bytes32 internal constant GAMMA_MODIFY_INFO_TYPE_HASH = keccak256(GAMMA_MODIFY_INFO_TYPE);

    /// @notice hash an GammaModifyInfo object
    /// @param info The GammaModifyInfo object to hash
    function hash(GammaModifyInfo memory info) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                GAMMA_MODIFY_INFO_TYPE_HASH,
                info.expiration,
                info.lowerLimit,
                info.upperLimit,
                info.hedgeInterval,
                info.sqrtPriceTrigger,
                info.minSlippageTolerance,
                info.maxSlippageTolerance
            )
        );
    }
}

struct GammaOrder {
    OrderInfo info;
    uint64 pairId;
    uint256 positionId;
    address entryTokenAddress;
    int256 quantity;
    int256 quantitySqrt;
    int256 marginAmount;
    bool closePosition;
    int256 limitValue;
    GammaModifyInfo modifyInfo;
}

/// @notice helpers for handling general order objects
library GammaOrderLib {
    using OrderInfoLib for OrderInfo;

    bytes internal constant GAMMA_ORDER_TYPE = abi.encodePacked(
        "GammaOrder(",
        "OrderInfo info,",
        "uint64 pairId,",
        "uint256 positionId,",
        "address entryTokenAddress,",
        "int256 quantity,",
        "int256 quantitySqrt,",
        "int256 marginAmount,",
        "bool closePosition,",
        "int256 limitValue,",
        "GammaModifyInfo modifyInfo)"
    );

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    bytes internal constant ORDER_TYPE =
        abi.encodePacked(GAMMA_ORDER_TYPE, GammaModifyInfoLib.GAMMA_MODIFY_INFO_TYPE, OrderInfoLib.ORDER_INFO_TYPE);
    bytes32 internal constant GAMMA_ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    string internal constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("GammaOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(GammaOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                GAMMA_ORDER_TYPE_HASH,
                order.info.hash(),
                order.pairId,
                order.positionId,
                order.entryTokenAddress,
                order.quantity,
                order.quantitySqrt,
                order.marginAmount,
                order.closePosition,
                order.limitValue,
                GammaModifyInfoLib.hash(order.modifyInfo)
            )
        );
    }

    function resolve(GammaOrder memory gammaOrder, bytes memory sig) internal pure returns (ResolvedOrder memory) {
        uint256 amount = gammaOrder.marginAmount > 0 ? uint256(gammaOrder.marginAmount) : 0;

        return ResolvedOrder(gammaOrder.info, gammaOrder.entryTokenAddress, amount, hash(gammaOrder), sig);
    }
}
