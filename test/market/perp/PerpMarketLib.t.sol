// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {PerpMarketLib} from "../../../src/markets/perp/PerpMarketLib.sol";
import {IPredyPool} from "../../../src/interfaces/IPredyPool.sol";

contract TestPerpMarketLib is Test {
    function testCalculateTradeAmount(int256 currentPositionAmount, int256 tradeAmount) public {
        bool reduceOnly = false;
        bool closePosition = false;

        assertEq(
            PerpMarketLib.getFinalTradeAmount(currentPositionAmount, tradeAmount, reduceOnly, closePosition),
            tradeAmount
        );
    }

    function testCalculateTradeAmountWithReduceOnly(int256 tradeAmount) public {
        tradeAmount = int256(bound(tradeAmount, -2 ** 100, 2 ** 100));

        bool reduceOnly = true;
        bool closePosition = false;
        int256 currentPositionAmount = 1e6;

        int256 result = PerpMarketLib.getFinalTradeAmount(currentPositionAmount, tradeAmount, reduceOnly, closePosition);

        if (-1e6 <= tradeAmount && tradeAmount < 0) {
            assertEq(result, tradeAmount);
        } else if (tradeAmount < -1e6) {
            assertEq(result, -1e6);
        } else {
            assertEq(result, 0);
        }
    }

    function testCalculateTradeAmountWithClosePosition(int256 currentPositionAmount, int256 tradeAmount) public {
        currentPositionAmount = int256(bound(currentPositionAmount, -2 ** 100, 2 ** 100));
        tradeAmount = int256(bound(tradeAmount, -2 ** 100, 2 ** 100));

        bool reduceOnly = false;
        bool closePosition = true;

        assertEq(
            PerpMarketLib.getFinalTradeAmount(currentPositionAmount, tradeAmount, reduceOnly, closePosition),
            -currentPositionAmount
        );
    }

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
