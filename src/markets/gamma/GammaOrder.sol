// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {OrderInfo, OrderInfoLib} from "../../libraries/orders/OrderInfoLib.sol";
import {IFillerMarket} from "../../interfaces/IFillerMarket.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {ResolvedOrder} from "../../libraries/orders/ResolvedOrder.sol";

struct GammaOrder {
    OrderInfo info;
    uint64 pairId;
    address entryTokenAddress;
    int256 tradeAmount;
    int256 tradeAmountSqrt;
    int256 marginAmount;
    uint256 hedgeInterval;
    uint256 sqrtPriceTrigger;
    uint64 maxSlippageTolerance;
    address validatorAddress;
    bytes validationData;
}

/// @notice helpers for handling general order objects
library GammaOrderLib {
    using OrderInfoLib for OrderInfo;

    bytes internal constant GENERAL_ORDER_TYPE = abi.encodePacked(
        "GammaOrder(",
        "OrderInfo info,",
        "uint64 pairId,",
        "address entryTokenAddress,",
        "int256 tradeAmount,",
        "int256 tradeAmountSqrt,",
        "int256 marginAmount,",
        "uint256 hedgeInterval,",
        "uint256 sqrtPriceTrigger,",
        "uint64 maxSlippageTolerance,",
        "address validatorAddress,",
        "bytes validationData)"
    );

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    bytes internal constant ORDER_TYPE = abi.encodePacked(GENERAL_ORDER_TYPE, OrderInfoLib.ORDER_INFO_TYPE);
    bytes32 internal constant GENERAL_ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    string internal constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("GammaOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(GammaOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                GENERAL_ORDER_TYPE_HASH,
                order.info.hash(),
                order.pairId,
                order.entryTokenAddress,
                order.tradeAmount,
                order.tradeAmountSqrt,
                order.marginAmount,
                order.hedgeInterval,
                order.sqrtPriceTrigger,
                order.maxSlippageTolerance,
                order.validatorAddress,
                keccak256(order.validationData)
            )
        );
    }

    function resolve(GammaOrder memory gammaOrder, bytes memory sig) internal pure returns (ResolvedOrder memory) {
        uint256 amount = gammaOrder.marginAmount > 0 ? uint256(gammaOrder.marginAmount) : 0;

        return ResolvedOrder(gammaOrder.info, gammaOrder.entryTokenAddress, amount, hash(gammaOrder), sig);
    }
}
