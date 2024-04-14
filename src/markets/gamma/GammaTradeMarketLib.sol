// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Bps} from "../../../src/libraries/math/Bps.sol";

library GammaTradeMarketLib {
    struct AuctionParams {
        uint32 minSlippageTolerance;
        uint32 maxSlippageTolerance;
        uint16 auctionPeriod;
        uint32 auctionRange;
    }

    function calculateSlippageTolerance(uint256 startTime, uint256 currentTime, AuctionParams memory auctionParams)
        internal
        pure
        returns (uint256)
    {
        if (currentTime <= startTime) {
            return auctionParams.minSlippageTolerance;
        }

        uint256 elapsed = (currentTime - startTime) * Bps.ONE / auctionParams.auctionPeriod;

        if (elapsed > Bps.ONE) {
            return auctionParams.maxSlippageTolerance;
        }

        return (
            auctionParams.minSlippageTolerance
                + elapsed * (auctionParams.maxSlippageTolerance - auctionParams.minSlippageTolerance) / Bps.ONE
        );
    }

    /**
     * @notice Calculate slippage tolerance by price
     * trader want to trade in price1 >= price2,
     * slippage tolerance will be increased if price1 <= price2
     */
    function calculateSlippageToleranceByPrice(uint256 price1, uint256 price2, AuctionParams memory auctionParams)
        internal
        pure
        returns (uint256)
    {
        if (price2 <= price1) {
            return auctionParams.minSlippageTolerance;
        }

        uint256 ratio = (price2 * Bps.ONE / price1 - Bps.ONE);

        if (ratio > auctionParams.auctionRange) {
            return auctionParams.maxSlippageTolerance;
        }

        return (
            auctionParams.minSlippageTolerance
                + ratio * (auctionParams.maxSlippageTolerance - auctionParams.minSlippageTolerance)
                    / auctionParams.auctionRange
        );
    }
}
