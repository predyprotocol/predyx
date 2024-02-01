// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/libraries/Constants.sol";

contract OrderValidatorUtils {
    function calculateLimitPrice(uint256 quoteAmount, uint256 baseAmount) internal pure returns (uint256) {
        return quoteAmount * Constants.Q96 / baseAmount;
    }

    function encodePerpOrderParams(uint64 deadline, uint64 pairId, uint8 leverage)
        internal
        pure
        returns (bytes32 params)
    {
        assembly {
            params := add(deadline, add(shl(64, pairId), shl(128, leverage)))
        }
    }

    function encodeParams(bool isLimit, uint32 decay, uint64 startTime, uint64 endTime, uint64 deadline)
        internal
        pure
        returns (bytes32 params)
    {
        uint32 isLimitUint = isLimit ? 1 : 0;

        assembly {
            params :=
                add(deadline, add(shl(64, startTime), add(shl(128, endTime), add(shl(192, decay), shl(224, isLimitUint)))))
        }
    }
}
