// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SpotMarketV1} from "./SpotMarketV1.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {SpotOrder} from "./SpotOrder.sol";
import {OrderInfo} from "../../libraries/orders/OrderInfoLib.sol";
import {SpotDutchOrderValidationData} from "./SpotDutchOrderValidator.sol";
import {SpotLimitOrderValidationData} from "./SpotLimitOrderValidator.sol";
import {Math} from "../../libraries/math/Math.sol";
import {L2Decoder} from "../L2Decoder.sol";

struct SpotOrderV2 {
    address trader;
    uint256 nonce;
    address quoteToken;
    address baseToken;
    int256 baseTokenAmount;
    uint256 quoteTokenAmount;
    bytes32 params1;
    bytes32 params2;
}

/**
 * @notice Spot market contract for Layer2.
 * Optimizing calldata size in this contract since L2 calldata is relatively expensive.
 */
contract SpotMarket is SpotMarketV1 {
    address internal immutable DUTCH_ORDER_VALIDATOR;
    address internal immutable LIMIT_ORDER_VALIDATOR;

    constructor(address permit2Address, address dutchOrderValidator, address limitOrderValidator)
        SpotMarketV1(permit2Address)
    {
        DUTCH_ORDER_VALIDATOR = dutchOrderValidator;
        LIMIT_ORDER_VALIDATOR = limitOrderValidator;
    }

    function executeOrderV2(SpotOrderV2 memory orderV2, bytes memory sig, SettlementParams memory settlementParams)
        external
        returns (int256 quoteTokenAmount)
    {
        (uint64 deadline, address validatorAddress, bytes memory validationData) =
            getValidationDate(orderV2.params1, orderV2.params2);

        SpotOrder memory order = SpotOrder({
            info: OrderInfo(address(this), orderV2.trader, orderV2.nonce, deadline),
            quoteToken: orderV2.quoteToken,
            baseToken: orderV2.baseToken,
            baseTokenAmount: orderV2.baseTokenAmount,
            quoteTokenAmount: orderV2.quoteTokenAmount,
            validatorAddress: validatorAddress,
            validationData: validationData
        });

        return _executeOrder(order, sig, settlementParams);
    }

    function getValidationDate(bytes32 params1, bytes32 params2)
        internal
        view
        returns (uint64 deadline, address validatorAddress, bytes memory validationData)
    {
        bool isLimit;
        uint64 startTime;
        uint64 endTime;
        uint128 startAmount;
        uint128 endAmount;

        (isLimit, startTime, endTime, deadline, startAmount, endAmount) =
            L2Decoder.decodeSpotOrderParams(params1, params2);

        if (isLimit) {
            validatorAddress = LIMIT_ORDER_VALIDATOR;
            validationData = abi.encode(SpotLimitOrderValidationData(startAmount));
        } else {
            validatorAddress = DUTCH_ORDER_VALIDATOR;
            validationData = abi.encode(SpotDutchOrderValidationData(startAmount, endAmount, startTime, endTime));
        }
    }
}
