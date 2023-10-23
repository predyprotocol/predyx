// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {OrderInfo, OrderInfoLib} from "./OrderInfoLib.sol";
import {IFillerMarket} from "../../interfaces/IFillerMarket.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {ResolvedOrder} from "./ResolvedOrder.sol";
import "../Constants.sol";

struct GeneralOrder {
    OrderInfo info;
    uint256 positionId;
    uint64 pairId;
    int256 tradeAmount;
    int256 tradeAmountSqrt;
    int256 marginAmount;
    uint256 marginRatio;
    address validatorAddress;
    bytes validationData;
}

/// @notice helpers for handling general order objects
library GeneralOrderLib {
    using OrderInfoLib for OrderInfo;

    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    error TriggerNotMatched();

    bytes internal constant GENERAL_ORDER_TYPE = abi.encodePacked(
        "GeneralOrder(",
        "OrderInfo info,",
        "uint256 positionId,",
        "uint64 pairId,",
        "int256 tradeAmount,",
        "int256 tradeAmountSqrt,",
        "int256 marginAmount,",
        "uint256 marginRatio" "address validatorAddress" "bytes validationData)"
    );

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    bytes internal constant ORDER_TYPE = abi.encodePacked(GENERAL_ORDER_TYPE, OrderInfoLib.ORDER_INFO_TYPE);
    bytes32 internal constant GENERAL_ORDER_TYPE_HASH = keccak256(GENERAL_ORDER_TYPE);

    string internal constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("GeneralOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(GeneralOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                GENERAL_ORDER_TYPE_HASH,
                order.info.hash(),
                order.positionId,
                order.pairId,
                order.tradeAmount,
                order.tradeAmountSqrt,
                order.marginAmount,
                order.marginRatio,
                order.validatorAddress,
                order.validationData
            )
        );
    }

    function resolve(IFillerMarket.SignedOrder memory order, address token)
        internal
        pure
        returns (GeneralOrder memory generalOrder, ResolvedOrder memory)
    {
        generalOrder = abi.decode(order.order, (GeneralOrder));

        uint256 amount = generalOrder.marginAmount > 0 ? uint256(generalOrder.marginAmount) : 0;

        return (generalOrder, ResolvedOrder(generalOrder.info, token, amount, hash(generalOrder), order.sig));
    }
}
