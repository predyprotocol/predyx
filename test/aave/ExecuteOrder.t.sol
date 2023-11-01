// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {PerpOrder} from "../../src/libraries/orders/PerpOrder.sol";

contract TestAaveExecuteOrder is TestAavePerp {
    address _fillerAddress;

    function setUp() public override {
        TestAavePerp.setUp();

        _fillerAddress = msg.sender;
    }

    function testAaveExecuteOrderSucceeds() public {
        PerpOrder memory order = PerpOrder(
            OrderInfo(address(_aavePerp), from1, _fillerAddress, 0, block.timestamp + 100),
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
    }
}
