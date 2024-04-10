// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import {GammaModifyInfo} from "./GammaOrder.sol";

library L2GammaDecoder {
    function decodeGammaModifyInfo(bytes32 args, uint256 lowerLimit, uint256 upperLimit)
        internal
        pure
        returns (GammaModifyInfo memory)
    {
        (
            bool isEnabled,
            uint64 expiration,
            uint32 hedgeInterval,
            uint32 sqrtPriceTrigger,
            uint32 minSlippageTolerance,
            uint32 maxSlippageTolerance,
            uint16 auctionPeriod,
            uint32 auctionRange
        ) = decodeGammaModifyParam(args);

        return GammaModifyInfo(
            isEnabled,
            expiration,
            lowerLimit,
            upperLimit,
            hedgeInterval,
            sqrtPriceTrigger,
            minSlippageTolerance,
            maxSlippageTolerance,
            auctionPeriod,
            auctionRange
        );
    }

    function decodeGammaModifyParam(bytes32 args)
        internal
        pure
        returns (
            bool isEnabled,
            uint64 expiration,
            uint32 hedgeInterval,
            uint32 sqrtPriceTrigger,
            uint32 minSlippageTolerance,
            uint32 maxSlippageTolerance,
            uint16 auctionPeriod,
            uint32 auctionRange
        )
    {
        uint32 isEnabledUint = 0;

        assembly {
            expiration := and(args, 0xFFFFFFFFFFFFFFFF)
            hedgeInterval := and(shr(64, args), 0xFFFFFFFF)
            sqrtPriceTrigger := and(shr(96, args), 0xFFFFFFFF)
            minSlippageTolerance := and(shr(128, args), 0xFFFFFFFF)
            maxSlippageTolerance := and(shr(160, args), 0xFFFFFFFF)
            auctionRange := and(shr(192, args), 0xFFFFFFFF)
            isEnabledUint := and(shr(224, args), 0xFFFF)
            auctionPeriod := and(shr(240, args), 0xFFFF)
        }

        if (isEnabledUint == 1) {
            isEnabled = true;
        } else {
            isEnabled = false;
        }
    }
}
