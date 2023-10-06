// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/PriceFeed.sol";

contract MockPriceFeed {
    int256 latestAnswer;

    function setAnswer(int256 answer) external {
        latestAnswer = answer;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 0;
        answer = latestAnswer;
        startedAt = 0;
        updatedAt = 0;
        answeredInRound = 0;
    }
}

contract PriceFeedTest is Test {
    PriceFeed priceFeed;

    MockPriceFeed mockQuotePriceFeed;
    MockPriceFeed mockBasePriceFeed;

    function setUp() public {
        mockQuotePriceFeed = new MockPriceFeed();
        mockBasePriceFeed = new MockPriceFeed();

        priceFeed = new PriceFeed(address(mockQuotePriceFeed), address(mockBasePriceFeed));
    }

    function testGetSqrtPrice() public {
        mockBasePriceFeed.setAnswer(1620 * 1e8);
        mockQuotePriceFeed.setAnswer(1e8);

        assertEq(priceFeed.getSqrtPrice(), 3188872028057322785329830);
    }

    function testGetSqrtPriceFuzz(uint256 a, uint256 b) public {
        a = bound(a, 1, 1e14);
        b = bound(a, 1, 2 * 1e8);

        mockBasePriceFeed.setAnswer(int256(a));
        mockQuotePriceFeed.setAnswer(int256(b));

        assertGt(priceFeed.getSqrtPrice(), 0);
    }
}
