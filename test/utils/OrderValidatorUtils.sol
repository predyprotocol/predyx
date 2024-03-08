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

    function encodePerpOrderV3Params(
        uint64 deadline,
        uint64 pairId,
        uint8 leverage,
        bool reduceOnly,
        bool closePosition
    ) internal pure returns (bytes32 params) {
        uint8 reduceOnlyUint = reduceOnly ? 1 : 0;
        uint8 closePositionUint = closePosition ? 1 : 0;

        assembly {
            params :=
                add(
                    deadline,
                    add(
                        shl(64, pairId), add(shl(128, leverage), add(shl(136, reduceOnlyUint), shl(144, closePositionUint)))
                    )
                )
        }
    }

    function encodeParams(
        bool isLimit,
        uint64 startTime,
        uint64 endTime,
        uint64 deadline,
        uint128 startAmount,
        uint128 endAmount
    ) internal pure returns (bytes32 params1, bytes32 params2) {
        uint32 isLimitUint = isLimit ? 1 : 0;

        assembly {
            params1 := add(deadline, add(shl(64, startTime), add(shl(128, endTime), shl(192, isLimitUint))))
        }

        assembly {
            params2 := add(startAmount, shl(128, endAmount))
        }
    }
}
