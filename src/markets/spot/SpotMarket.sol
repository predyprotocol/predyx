// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SpotMarketV1} from "./SpotMarketV1.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {SpotOrder} from "./SpotOrder.sol";
import {OrderInfo} from "../../libraries/orders/OrderInfoLib.sol";
import {SpotDutchOrderValidationData} from "./SpotDutchOrderValidator.sol";
import {SpotLimitOrderValidationData} from "./SpotLimitOrderValidator.sol";
import {Math} from "../../libraries/math/Math.sol";
import {L2Decoder} from "./L2Decoder.sol";

struct SpotOrderV2 {
    address trader;
    uint256 nonce;
    address quoteToken;
    address baseToken;
    int256 baseTokenAmount;
    uint256 quoteTokenAmount;
    bytes32 params1;
    uint256 params2;
}

/**
 * @notice Spot market contract for Layer2.
 * Optimizing calldata size in this contract since L2 calldata is relatively expensive.
 */
contract SpotMarket is SpotMarketV1 {
    address internal immutable _dutchOrderValidator;
    address internal immutable _limitOrderValidator;

    constructor(address permit2Address, address dutchOrderValidator, address limitOrderValidator)
        SpotMarketV1(permit2Address)
    {
        _dutchOrderValidator = dutchOrderValidator;
        _limitOrderValidator = limitOrderValidator;
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

    function getValidationDate(bytes32 params1, uint256 params2)
        internal
        view
        returns (uint64 deadline, address validatorAddress, bytes memory validationData)
    {
        bool isLimit;
        uint32 decay;
        uint64 startTime;
        uint64 endTime;

        (isLimit, decay, startTime, endTime, deadline) = L2Decoder.decodeSpotOrderParams(params1);

        if (isLimit) {
            validatorAddress = _limitOrderValidator;
            validationData = abi.encode(SpotLimitOrderValidationData(params2));
        } else {
            validatorAddress = _dutchOrderValidator;
            validationData = abi.encode(
                SpotDutchOrderValidationData(params2, params2 * (10000 + decay - 10000) / 10000, startTime, endTime)
            );
        }
    }
}
