// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

library L2Decoder {
    function decodeSpotOrderParams(bytes32 args)
        internal
        pure
        returns (bool isLimit, uint32 decay, uint64 startTime, uint64 endTime, uint64 deadline)
    {
        uint32 isLimitUint;

        assembly {
            deadline := and(args, 0xFFFFFFFFFFFFFFFF)
            startTime := and(shr(64, args), 0xFFFFFFFFFFFFFFFF)
            endTime := and(shr(128, args), 0xFFFFFFFFFFFFFFFF)
            decay := and(shr(192, args), 0xFFFFFFFF)
            isLimitUint := and(shr(224, args), 0xFFFFFFFF)
        }

        if (isLimitUint == 1) {
            isLimit = true;
        } else {
            isLimit = false;
        }
    }

    function decodePerpOrderParams(bytes32 args)
        internal
        pure
        returns (uint64 deadline, uint64 pairId, uint8 leverage)
    {
        assembly {
            deadline := and(args, 0xFFFFFFFFFFFFFFFF)
            pairId := and(shr(64, args), 0xFFFFFFFFFFFFFFFF)
            leverage := and(shr(128, args), 0xFF)
        }
    }
}
