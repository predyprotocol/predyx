// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@solmate/src/utils/FixedPointMathLib.sol";
import "./vendors/AggregatorV3Interface.sol";
import "./libraries/Constants.sol";

contract PriceFeed {
    address quotePrice;
    address basePrice;

    constructor(address _quotePrice, address _basePrice) {
        quotePrice = _quotePrice;
        basePrice = _basePrice;
    }

    function getSqrtPrice() external view returns (uint256 sqrtPrice) {
        (, int256 quoteAnswer,,,) = AggregatorV3Interface(quotePrice).latestRoundData();
        (, int256 baseAnswer,,,) = AggregatorV3Interface(basePrice).latestRoundData();

        require(quoteAnswer > 0 && baseAnswer > 0);

        uint256 price = uint256(baseAnswer) * Constants.Q96 / uint256(quoteAnswer);
        price = price * Constants.Q96 / 1e12;

        sqrtPrice = FixedPointMathLib.sqrt(price);
    }
}
