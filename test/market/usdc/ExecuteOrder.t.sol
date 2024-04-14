// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import {OrderInfo} from "../../../src/libraries/orders/OrderInfoLib.sol";
import {PerpMarketLib} from "../../../src/markets/perp/PerpMarketLib.sol";

contract TestPerpMarketExecuteOrder is TestUSDCPerpMarket {
    address _fillerAddress;

    function setUp() public override {
        TestUSDCPerpMarket.setUp();

        _fillerAddress = address(this);
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

        PerpOrderV3 memory order = PerpOrderV3(
            OrderInfo(address(perpMarket), _from, 0, block.timestamp + 100),
            1,
            address(_usdc),
            "Sell",
            1e17,
            200 * 1e6,
            Constants.Q96 * 1800 * 1e6 / 1e18,
            0,
            2,
            false,
            false,
            abi.encode(PerpMarketLib.AuctionParams(0, 0, 0, 0))
        );

        IFillerMarket.SignedOrder memory signedOrder = _createSignedOrder(order, _fromPrivateKey);

        IPredyPool.TradeResult memory tradeResult =
            perpMarket.executeOrderV3(signedOrder, _getSettlementDataV3(Constants.Q96 * 2000 * 1e6 / 1e18));

        assertEq(tradeResult.payoff.perpEntryUpdate, 199999999);
        assertEq(tradeResult.payoff.perpPayoff, 0);
    }
}
