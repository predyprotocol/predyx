// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

/// @notice helpers for handling dutch auction
library DecayLib {
    error EndTimeBeforeStartTime();

    function decay(uint256 startPrice, uint256 endPrice, uint256 decayStartTime, uint256 decayEndTime)
        internal
        view
        returns (uint256 decayedPrice)
    {
        if (decayEndTime < decayStartTime) {
            revert EndTimeBeforeStartTime();
        } else if (decayEndTime <= block.timestamp) {
            decayedPrice = endPrice;
        } else if (decayStartTime >= block.timestamp) {
            decayedPrice = startPrice;
        } else {
            uint256 elapsed = block.timestamp - decayStartTime;
            uint256 duration = decayEndTime - decayStartTime;

            if (endPrice < startPrice) {
                decayedPrice = startPrice - (startPrice - endPrice) * elapsed / duration;
            } else {
                decayedPrice = startPrice + (endPrice - startPrice) * elapsed / duration;
            }
        }
    }
}
