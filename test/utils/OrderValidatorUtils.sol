// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/libraries/Constants.sol";

contract OrderValidatorUtils {
    function calculateLimitPrice(uint256 quoteAmount, uint256 baseAmount) internal pure returns (uint256) {
        return quoteAmount * Constants.Q96 / baseAmount;
    }
}