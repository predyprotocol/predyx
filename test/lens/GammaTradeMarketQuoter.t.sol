// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../../src/lens/PredyPoolQuoter.sol";
import "../../src/lens/GammaTradeMarketQuoter.sol";
import "../../src/markets/gamma/GammaTradeMarket.sol";
import "../../src/markets/validators/GeneralDutchOrderValidator.sol";
import {OrderInfo} from "../../src/libraries/orders/OrderInfoLib.sol";
import {Constants} from "../../src/libraries/Constants.sol";
import "../../src/settlements/UniswapSettlement.sol";

contract TestPredictMarketQuoter is TestLens {
    GammaTradeMarketQuoter _quoter;

    GeneralDutchOrderValidator dutchOrderValidator;

    address from;

    function setUp() public override {
        TestLens.setUp();

        IPermit2 permit2 = IPermit2(deployCode("../artifacts/Permit2.sol:Permit2"));

        GammaTradeMarket gammaTradeMarket = new GammaTradeMarket(predyPool, address(permit2), address(this));

        _quoter = new GammaTradeMarketQuoter(gammaTradeMarket, _predyPoolQuoter);

        from = vm.addr(1);

        predyPool.createVault(1);

        dutchOrderValidator = new GeneralDutchOrderValidator();
    }

    function testQuoteExecuteOrder() public {
        GammaOrder memory order = GammaOrder(
            OrderInfo(address(0), from, 0, block.timestamp + 100),
            1,
            address(currency1),
            -1000,
            900,
            2 * 1e6,
            12 hours,
            0,
            1000,
            address(dutchOrderValidator),
            abi.encode(
                GeneralDutchOrderValidationData(
                    Constants.Q96, Bps.ONE, Bps.ONE, 101488915, block.timestamp, block.timestamp + 60
                )
            )
        );

        ISettlement.SettlementData memory settlementData = uniswapSettlement.getSettlementParams(
            abi.encodePacked(address(currency0), uint24(500), address(currency1)),
            0,
            address(currency1),
            address(currency0),
            0
        );

        IPredyPool.TradeResult memory tradeResult = _quoter.quoteExecuteOrder(order, settlementData);

        assertEq(tradeResult.payoff.perpEntryUpdate, 980);
        assertEq(tradeResult.payoff.sqrtEntryUpdate, -1782);
        assertEq(tradeResult.payoff.perpPayoff, 0);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
    }
}
