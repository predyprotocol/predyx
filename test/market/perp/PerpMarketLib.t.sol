// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {PerpMarketLib} from "../../../src/markets/perp/PerpMarketLib.sol";
import {IPredyPool} from "../../../src/interfaces/IPredyPool.sol";

contract TestPerpMarketLib is Test {
    function testValidateTradeBuy(uint256 entryUpdate) public {
        entryUpdate = bound(entryUpdate, 0, 2 ** 100);

        IPredyPool.TradeResult memory tradeResult;

        int256 tradeAmount = 1000;
        uint256 limitPrice = 90 * 2 ** 96;
        uint256 stopPrice = 110 * 2 ** 96;

        tradeResult.payoff.perpEntryUpdate = int256(entryUpdate);
        tradeResult.payoff.perpPayoff = 0;
        tradeResult.sqrtTwap = 10 * 2 ** 96;

        bytes memory auctionData = abi.encode(PerpMarketLib.AuctionParams(1001000, 1005000, 0, 10000));

        if (entryUpdate > 90000) {
            vm.expectRevert(PerpMarketLib.LimitStopOrderDoesNotMatch.selector);
        }
        PerpMarketLib.validateTrade(tradeResult, tradeAmount, limitPrice, stopPrice, auctionData);
    }

    function testValidateLimitPrice(uint256 tradePrice, int256 tradeAmount, uint256 limitPrice) public {
        bool result = PerpMarketLib.validateLimitPrice(tradePrice, tradeAmount, limitPrice);

        if (tradeAmount > 0) {
            // buy
            if (tradePrice <= limitPrice) {
                assertTrue(result);
            } else {
                assertFalse(result);
            }
        } else if (tradeAmount < 0) {
            // sell
            if (tradePrice >= limitPrice) {
                assertTrue(result);
            } else {
                assertFalse(result);
            }
        } else {
            // amount is 0
            assertFalse(result);
        }
    }

    function testValidateStopPriceBuyTradePrice(uint256 tradePrice) public {
        // 0.1% - 0.5% (0-1%)
        bytes memory auctionData = abi.encode(PerpMarketLib.AuctionParams(1001000, 1005000, 0, 10000));

        uint256 oraclePrice = 10000;
        int256 tradeAmount = 1000;
        uint256 stopPrice = 10000;

        bool result = PerpMarketLib.validateStopPrice(oraclePrice, tradePrice, tradeAmount, stopPrice, auctionData);

        if (tradePrice <= 10010) {
            assertTrue(result);
        } else {
            assertFalse(result);
        }
    }

    function testValidateStopPriceSellTradePrice(uint256 tradePrice) public {
        // 0.1% - 0.5% (0-1%)
        bytes memory auctionData = abi.encode(PerpMarketLib.AuctionParams(1001000, 1005000, 0, 10000));

        uint256 oraclePrice = 10000;
        int256 tradeAmount = -1000;
        uint256 stopPrice = 10000;

        bool result = PerpMarketLib.validateStopPrice(oraclePrice, tradePrice, tradeAmount, stopPrice, auctionData);

        if (tradePrice >= 9990) {
            assertTrue(result);
        } else {
            assertFalse(result);
        }
    }

    function testValidateStopPriceBuyOraclePrice(uint256 oraclePrice) public {
        oraclePrice = bound(oraclePrice, 0, 2 ** 100);

        // 0.1% - 0.5% (0-1%)
        bytes memory auctionData = abi.encode(PerpMarketLib.AuctionParams(1001000, 1005000, 0, 10000));

        uint256 tradePrice = 10000;
        int256 tradeAmount = 1000;
        uint256 stopPrice = 10000;

        bool result = PerpMarketLib.validateStopPrice(oraclePrice, tradePrice, tradeAmount, stopPrice, auctionData);

        if (oraclePrice >= 10000) {
            assertTrue(result);
        } else {
            assertFalse(result);
        }
    }

    function testValidateStopPriceSellOraclePrice(uint256 oraclePrice) public {
        oraclePrice = bound(oraclePrice, 0, 2 ** 100);

        // 0.1% - 0.5% (0-1%)
        bytes memory auctionData = abi.encode(PerpMarketLib.AuctionParams(1001000, 1005000, 0, 10000));

        uint256 tradePrice = 10000;
        int256 tradeAmount = -1000;
        uint256 stopPrice = 10000;

        bool result = PerpMarketLib.validateStopPrice(oraclePrice, tradePrice, tradeAmount, stopPrice, auctionData);

        if (oraclePrice <= 10000) {
            assertTrue(result);
        } else {
            assertFalse(result);
        }
    }

    function testValidateMarketOrder(uint256 tradePrice) public {
        vm.warp(1000);
        bytes memory auctionData = abi.encode(PerpMarketLib.AuctionParams(1001000, 1005000, 0, 1000));

        int256 tradeAmount = 1000;

        bool result = PerpMarketLib.validateMarketOrder(tradePrice, tradeAmount, auctionData);

        if (tradePrice > 1005000) {
            assertFalse(result);
        } else {
            assertTrue(result);
        }
    }
}
