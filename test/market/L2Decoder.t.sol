// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {L2Decoder} from "../../src/markets/L2Decoder.sol";
import {OrderValidatorUtils} from "../utils/OrderValidatorUtils.sol";

contract TestL2Decoder is Test, OrderValidatorUtils {
    function testSucceedsToDecodeSpotParams(
        bool isLimit,
        uint32 decay,
        uint64 startTime,
        uint32 untilEndTime,
        uint64 deadline
    ) public {
        bytes32 params = encodeParams(isLimit, decay, startTime, untilEndTime, deadline);

        (bool a, uint32 b, uint64 c, uint64 d, uint64 e) = L2Decoder.decodeSpotOrderParams(params);

        assertEq(a, isLimit);
        assertEq(b, decay);
        assertEq(c, startTime);
        assertEq(d, untilEndTime);
        assertEq(e, deadline);
    }

    function testSucceedsToDecodePerpParams() public {
        bytes32 params = bytes32(0x0000000000000000000000000000000000000000000000010000000065e3649e);

        (uint64 deadline, uint64 pairId, uint8 leverage) = L2Decoder.decodePerpOrderParams(params);

        assertEq(deadline, 1);
        assertEq(pairId, 2);
        assertEq(leverage, 3);
    }
}
