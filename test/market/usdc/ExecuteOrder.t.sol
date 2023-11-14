// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";

contract TestPerpMarketExecuteOrder is TestPerpMarket {
    address _fillerAddress;

    function setUp() public override {
        TestPerpMarket.setUp();

        _fillerAddress = address(this);

        perpMarket.addFillerPool(pairId);

        perpMarket.depositToInsurancePool(pairId, 1000 * 1e6);
    }

    // executeOrder succeeds for open(pnl, interest, premium, borrow fee)
    function testExecuteOrderSucceedsForOpen() public {
        {
            uint256 deadline = block.timestamp + 100;

            (uint8 v, bytes32 r, bytes32 s) = _getPermitVer1Signature(
                _fromPrivateKey,
                _from,
                address(_permit2),
                type(uint256).max,
                0,
                deadline,
                0xa074269f06a6961e917f3c53d7204a31a08aec9a5f4a5801e8a8f837483b62a0
            );

            _usdc.permit(_from, address(_permit2), type(uint256).max, deadline, v, r, s);
        }

        PerpOrder memory order = PerpOrder(
            OrderInfo(address(perpMarket), _from, _fillerAddress, 0, block.timestamp + 100),
            0,
            1,
            address(_usdc),
            -1000,
            2 * 1e6,
            address(limitOrderValidator),
            abi.encode(PerpLimitOrderValidationData(0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, _fromPrivateKey);

        PerpMarket.PerpTradeResult memory tradeResult =
            perpMarket.executeOrder(signedOrder, settlement.getSettlementParams(address(_usdc), address(_weth), 1600));

        assertEq(tradeResult.entryUpdate, 160);
        assertEq(tradeResult.payoff, 0);
    }
}