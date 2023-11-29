// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {AggregatorV3Interface} from "./vendors/AggregatorV3Interface.sol";
import {Constants} from "./libraries/Constants.sol";

contract PriceFeedFactory {
    event PriceFeedCreated(address quotePrice, address basePrice, uint256 decimalsDiff, address priceFeed);

    function createPriceFeed(address quotePrice, address basePrice, uint256 decimalsDiff) external returns (address) {
        PriceFeed priceFeed = new PriceFeed(quotePrice, basePrice, decimalsDiff);

        emit PriceFeedCreated(quotePrice, basePrice, decimalsDiff, address(priceFeed));

        return address(priceFeed);
    }
}

contract PriceFeed {
    address private immutable _quotePriceFeed;
    address private immutable _basePriceFeed;
    uint256 private immutable _decimalsDiff;

    constructor(address quotePrice, address basePrice, uint256 decimalsDiff) {
        _quotePriceFeed = quotePrice;
        _basePriceFeed = basePrice;
        _decimalsDiff = decimalsDiff;
    }

    function getSqrtPrice() external view returns (uint256 sqrtPrice) {
        (, int256 quoteAnswer,,,) = AggregatorV3Interface(_quotePriceFeed).latestRoundData();
        (, int256 baseAnswer,,,) = AggregatorV3Interface(_basePriceFeed).latestRoundData();

        require(quoteAnswer > 0 && baseAnswer > 0);

        uint256 price = uint256(baseAnswer) * Constants.Q96 / uint256(quoteAnswer);
        price = price * Constants.Q96 / _decimalsDiff;

        sqrtPrice = FixedPointMathLib.sqrt(price);
    }
}
