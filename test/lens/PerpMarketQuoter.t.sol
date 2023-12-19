// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../../src/lens/PredyPoolQuoter.sol";
import "../../src/lens/PerpMarketQuoter.sol";
import "../../src/settlements/RevertSettlement.sol";
import "../../src/markets/validators/LimitOrderValidator.sol";
import {OrderInfo} from "../../src/libraries/orders/OrderInfoLib.sol";
import "../../src/settlements/UniswapSettlement.sol";

contract TestPerpMarketQuoter is TestLens {
    PerpMarketQuoter _quoter;

    LimitOrderValidator limitOrderValidator;

    address from;

    function setUp() public override {
        TestLens.setUp();

        IPermit2 permit2 = IPermit2(deployCode("../test-artifacts/Permit2.sol:Permit2"));

        PerpMarket perpMarket = new PerpMarket(predyPool, address(permit2), address(this), address(_predyPoolQuoter));

        _quoter = new PerpMarketQuoter(perpMarket);

        from = vm.addr(1);

        predyPool.createVault(1);

        limitOrderValidator = new LimitOrderValidator();
    }

    function testQuoteExecuteOrder() public {
        PerpOrder memory order = PerpOrder(
            OrderInfo(address(0), from, 0, block.timestamp + 100),
            1,
            address(currency1),
            -1000,
            2 * 1e6,
            0,
            0,
            0,
            2,
            address(limitOrderValidator),
            abi.encode(LimitOrderValidationData(0, 0, 0, 0))
        );

        ISettlement.SettlementData memory settlementData = uniswapSettlement.getSettlementParams(
            abi.encodePacked(address(currency0), uint24(500), address(currency1)),
            0,
            address(currency1),
            address(currency0),
            0
        );

        IPredyPool.TradeResult memory tradeResult = _quoter.quoteExecuteOrder(order, settlementData);

        assertEq(tradeResult.payoff.perpEntryUpdate, 998);
        assertEq(tradeResult.payoff.sqrtEntryUpdate, 0);
        assertEq(tradeResult.payoff.perpPayoff, 0);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
    }
}
