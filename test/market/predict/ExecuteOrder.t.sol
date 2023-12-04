// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import {OrderInfo} from "../../../src/libraries/orders/OrderInfoLib.sol";
import {Bps} from "../../../src/libraries/math/Bps.sol";

contract TestPredictExecuteOrder is TestPredictMarket {
    bytes normalSwapRoute;
    uint256 fromPrivateKey1;
    address from1;
    uint256 fromPrivateKey2;
    address from2;

    function setUp() public override {
        TestPredictMarket.setUp();

        registerPair(address(currency1), address(0));
        fillerMarket.updateQuoteTokenMap(1);

        predyPool.supply(1, true, 1e10);
        predyPool.supply(1, false, 1e10);

        normalSwapRoute = abi.encodePacked(address(currency0), uint24(500), address(currency1));

        fromPrivateKey1 = 0x12341234;
        from1 = vm.addr(fromPrivateKey1);
        fromPrivateKey2 = 0x1235678;
        from2 = vm.addr(fromPrivateKey2);

        currency1.mint(from1, type(uint128).max);
        currency1.mint(from2, type(uint128).max);

        vm.prank(from1);
        currency1.approve(address(permit2), type(uint256).max);

        vm.prank(from2);
        currency1.approve(address(permit2), type(uint256).max);
    }

    // executeOrder succeeds for open(pnl, interest, premium, borrow fee)
    function testExecuteOrderSucceedsForOpenPredictPosition() public {
        PredictOrder memory order = PredictOrder(
            OrderInfo(address(fillerMarket), from1, 0, block.timestamp + 100),
            1,
            10 minutes,
            address(currency1),
            -1000,
            900,
            2 * 1e6,
            address(dutchOrderValidator),
            abi.encode(
                GeneralDutchOrderValidationData(
                    Constants.Q96, Bps.ONE, Bps.ONE, 101488915, block.timestamp, block.timestamp + 60
                )
            )
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        IPredyPool.TradeResult memory tradeResult = fillerMarket.executeOrder(
            signedOrder, settlement.getSettlementParams(address(currency1), address(currency0), 10000)
        );

        assertEq(tradeResult.payoff.perpEntryUpdate, 1000);
        assertEq(tradeResult.payoff.sqrtEntryUpdate, -1800);
        assertEq(tradeResult.payoff.perpPayoff, 0);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
    }
}
