// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {AggregatorV3Interface} from "./vendors/AggregatorV3Interface.sol";
import {Constants} from "./libraries/Constants.sol";

contract PriceFeed {
    address private _quotePriceFeed;
    address private _basePriceFeed;

    constructor(address quotePrice, address basePrice) {
        _quotePriceFeed = quotePrice;
        _basePriceFeed = basePrice;
    }

    function getSqrtPrice() external view returns (uint256 sqrtPrice) {
        (, int256 quoteAnswer,,,) = AggregatorV3Interface(_quotePriceFeed).latestRoundData();
        (, int256 baseAnswer,,,) = AggregatorV3Interface(_basePriceFeed).latestRoundData();

        require(quoteAnswer > 0 && baseAnswer > 0);

        uint256 price = uint256(baseAnswer) * Constants.Q96 / uint256(quoteAnswer);
        price = price * Constants.Q96 / 1e12;

        sqrtPrice = FixedPointMathLib.sqrt(price);
    }
}
