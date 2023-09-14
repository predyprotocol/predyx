// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";

contract TestTrade is TestMarket {
    function setUp() public override {
        TestMarket.setUp();

        registerPair(address(currency1));

        predyPool.supply(1, true, 1e8);
        predyPool.supply(1, false, 1e8);
    }

    // trade succeeds for open(pnl, interest, premium, borrow fee)
    function testTradeSucceeds() public {
        IFillerMarket.Order memory order = IFillerMarket.Order(
            1,
            1,
            -1000,
            900,
            0,
            0,
            0,
            0,
            0
        );
        IFillerMarket.SignedOrder memory signedOrder = IFillerMarket.SignedOrder(
            order,
            ""
        );

        IPredyPool.TradeResult memory tradeResult = fillerMarket.trade(
            signedOrder, abi.encode(FillerMarket.SettlementParams(address(currency1), address(currency0)))
        );

        assertEq(tradeResult.payoff.perpEntryUpdate, 900);
        assertEq(tradeResult.payoff.sqrtEntryUpdate, -2000);
        assertEq(tradeResult.payoff.perpPayoff, 0);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
    }

    // trade succeeds for close
    // trade succeeds with market order
    // trade succeeds with limit order
    // trade succeeds with stop order

    // trade succeeds with 0 amount

    // trade succeeds with margin amount
    // trade fails if withdrawn margin amount is too large

    // trade succeeds with margin ratio
    // trade fails if margin ratio is invalid

    // trade fails if deadline passed
    // trade fails if signature is invalid
    // trade fails if nonce is invalid
    // trade fails if price is greater than limit
    // trade fails if price is less than limit
    // trade fails if filler pool is not enough
    // trade fails if the vault is danger

    // trade fails if pairId does not exist
}
