// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {L2Decoder} from "../../src/markets/L2Decoder.sol";
import {OrderValidatorUtils} from "../utils/OrderValidatorUtils.sol";

contract TestL2Decoder is Test, OrderValidatorUtils {
    function testSucceedsToDecodeSpotParams(
        bool isLimit,
        uint64 startTime,
        uint32 untilEndTime,
        uint64 deadline,
        uint128 startAmount,
        uint128 endAmount
    ) public {
        (bytes32 params1, bytes32 params2) =
            encodeParams(isLimit, startTime, untilEndTime, deadline, startAmount, endAmount);

        (bool a, uint64 b, uint64 c, uint64 d, uint128 e, uint128 f) = L2Decoder.decodeSpotOrderParams(params1, params2);

        assertEq(a, isLimit);
        assertEq(b, startTime);
        assertEq(c, untilEndTime);
        assertEq(d, deadline);
        assertEq(e, startAmount);
        assertEq(f, endAmount);
    }

    function testSucceedsToDecodePerpParams() public {
        bytes32 params = bytes32(0x0000000000000000000000000000000000000000000000010000000065e3649e);

        (uint64 deadline, uint64 pairId, uint8 leverage) = L2Decoder.decodePerpOrderParams(params);

        assertEq(deadline, 1709401246);
        assertEq(pairId, 1);
        assertEq(leverage, 0);
    }
}
