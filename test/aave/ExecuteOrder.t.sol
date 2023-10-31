// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {PerpOrder} from "../../src/libraries/orders/PerpOrder.sol";

contract TestAaveExecuteOrder is TestAavePerp {
    function setUp() public override {
        TestAavePerp.setUp();
    }

    function testAaveExecuteOrderSucceeds() public {
        PerpOrder memory order = PerpOrder(
            OrderInfo(address(_aavePerp), from1, 0, block.timestamp + 100),
            0,
            1,
            address(_usdc),
            -1000,
            2 * 1e6,
            address(limitOrderValidator),
            abi.encode(PerpLimitOrderValidationData(0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, fromPrivateKey1);

        ISettlement.SettlementData memory settlementData =
            settlement.getSettlementParams(address(_usdc), address(_weth), 10000);

        _aavePerp.executeOrder(signedOrder, settlementData);
        /*
        _weth.approve(address(_pool), 1000);
        _pool.supply(
            address(_weth),
            100,
            address(this),
            0
        );
        */
    }
}
