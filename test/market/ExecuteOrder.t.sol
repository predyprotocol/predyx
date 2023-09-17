// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";

contract TestExecuteOrder is TestMarket {
    bytes normalSwapRoute;

    function setUp() public override {
        TestMarket.setUp();

        registerPair(address(currency1));

        predyPool.supply(1, true, 1e8);
        predyPool.supply(1, false, 1e8);

        normalSwapRoute = abi.encodePacked(address(currency0), uint24(500), address(currency1));

        fillerMarket.depositToFillerPool(100 * 1e6);
    }

    // executeOrder succeeds for open(pnl, interest, premium, borrow fee)
    function testExecuteOrderSucceeds() public {
        IFillerMarket.Order memory order = IFillerMarket.Order(1, 1, -1000, 900, 0, 0, 0, 1e5, 0, 0);
        IFillerMarket.SignedOrder memory signedOrder = IFillerMarket.SignedOrder(order, "");

        IPredyPool.TradeResult memory tradeResult = fillerMarket.executeOrder(
            signedOrder,
            abi.encode(FillerMarket.SettlementParams(normalSwapRoute, 0, address(currency1), address(currency0)))
        );

        assertEq(tradeResult.payoff.perpEntryUpdate, 980);
        assertEq(tradeResult.payoff.sqrtEntryUpdate, -1782);
        assertEq(tradeResult.payoff.perpPayoff, 0);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
    }

    // netting
    function testExecuteOrderSucceedsWithNetting() public {
        {
            IFillerMarket.Order memory order = IFillerMarket.Order(1, 1, -1000, 0, 0, 0, 0, 1e5, 0, 0);
            IFillerMarket.SignedOrder memory signedOrder = IFillerMarket.SignedOrder(order, "");
            fillerMarket.executeOrder(
                signedOrder,
                abi.encode(FillerMarket.SettlementParams(normalSwapRoute, 0, address(currency1), address(currency0)))
            );
        }

        {
            IFillerMarket.Order memory order = IFillerMarket.Order(1, 1, 1000, 0, 1200, 0, 0, 1e5, 0, 0);
            IFillerMarket.SignedOrder memory signedOrder = IFillerMarket.SignedOrder(order, "");
            fillerMarket.executeOrder(
                signedOrder,
                abi.encode(FillerMarket.SettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0)))
            );
        }
    }

    // executeOrder succeeds for close
    // executeOrder succeeds with market order
    // executeOrder succeeds with limit order
    // executeOrder succeeds with stop order

    // executeOrder succeeds with 0 amount

    // executeOrder succeeds with margin amount
    // executeOrder fails if withdrawn margin amount is too large

    // executeOrder succeeds with margin ratio
    // executeOrder fails if margin ratio is invalid

    // executeOrder fails if deadline passed
    function testExecuteOrderFails_IfDeadlinePassed() public {
        IFillerMarket.Order memory order = IFillerMarket.Order(1, 1, 1000, 0, 1200, 0, 1, 1e5, 0, 0);
        IFillerMarket.SignedOrder memory signedOrder = IFillerMarket.SignedOrder(order, "");
        bytes memory settlementData =
            abi.encode(FillerMarket.SettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0)));

        vm.expectRevert(IFillerMarket.PastDeadline.selector);
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if signature is invalid
    // executeOrder fails if nonce is invalid

    // executeOrder fails if price is greater than limit
    function testExecuteOrderFails_IfPriceIsGreaterThanLimit() public {
        IFillerMarket.Order memory order = IFillerMarket.Order(1, 1, 1000, 0, 999, 0, 0, 1e5, 0, 0);
        IFillerMarket.SignedOrder memory signedOrder = IFillerMarket.SignedOrder(order, "");
        bytes memory settlementData =
            abi.encode(FillerMarket.SettlementParams(normalSwapRoute, 1500, address(currency1), address(currency0)));

        vm.expectRevert(IFillerMarket.PriceGreaterThanLimit.selector);
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if price is less than limit
    function testExecuteOrderFails_IfPriceIsLessThanLimit() public {
        IFillerMarket.Order memory order = IFillerMarket.Order(1, 1, -1000, 0, 1001, 0, 0, 1e5, 0, 0);
        IFillerMarket.SignedOrder memory signedOrder = IFillerMarket.SignedOrder(order, "");
        bytes memory settlementData =
            abi.encode(FillerMarket.SettlementParams(normalSwapRoute, 0, address(currency1), address(currency0)));

        vm.expectRevert(IFillerMarket.PriceLessThanLimit.selector);
        fillerMarket.executeOrder(signedOrder, settlementData);
    }

    // executeOrder fails if filler pool is not enough
    // executeOrder fails if the vault is danger

    // executeOrder fails if pairId does not exist
}
