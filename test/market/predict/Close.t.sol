// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import {OrderInfo} from "../../../src/libraries/orders/OrderInfoLib.sol";
import {Bps} from "../../../src/libraries/math/Bps.sol";

contract TestPredictClose is TestPredictMarket {
    bytes normalSwapRoute;
    uint256 fromPrivateKey1;
    address from1;

    function setUp() public override {
        TestPredictMarket.setUp();

        registerPair(address(currency1), address(0));
        fillerMarket.updateQuoteTokenMap(1);

        predyPool.supply(1, true, 1e10);
        predyPool.supply(1, false, 1e10);

        normalSwapRoute = abi.encodePacked(address(currency0), uint24(500), address(currency1));

        fromPrivateKey1 = 0x12341234;
        from1 = vm.addr(fromPrivateKey1);

        currency1.mint(from1, type(uint128).max);

        vm.prank(from1);
        currency1.approve(address(permit2), type(uint256).max);

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

        fillerMarket.executeOrder(signedOrder, _getSettlementData(Constants.Q96));
    }

    function testCloseSucceeds() public {
        PredictCloseOrder memory order = PredictCloseOrder(
            OrderInfo(address(fillerMarket), from1, 1, block.timestamp + 100),
            1,
            address(dutchOrderValidator),
            abi.encode(
                GeneralDutchOrderValidationData(
                    Constants.Q96, Bps.ONE, Bps.ONE, 101488915, block.timestamp, block.timestamp + 60
                )
            )
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        SettlementCallbackLib.SettlementParams memory settlementData = _getSettlementData(Constants.Q96);

        uint256 beforeBalance = currency1.balanceOf(from1);
        fillerMarket.close(signedOrder, settlementData);
        uint256 afterBalance = currency1.balanceOf(from1);

        // owner gets close value
        assertGt(afterBalance, beforeBalance);
    }
}
