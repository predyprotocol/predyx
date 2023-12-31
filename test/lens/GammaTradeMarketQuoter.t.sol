// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../../src/lens/PredyPoolQuoter.sol";
import "../../src/lens/GammaTradeMarketQuoter.sol";
import "../../src/markets/gamma/GammaTradeMarket.sol";
import "../../src/markets/validators/GeneralDutchOrderValidator.sol";
import {OrderInfo} from "../../src/libraries/orders/OrderInfoLib.sol";
import {Constants} from "../../src/libraries/Constants.sol";

contract TestGammaTradeMarketQuoter is TestLens {
    GammaTradeMarketQuoter _quoter;

    GeneralDutchOrderValidator dutchOrderValidator;

    address from;

    function setUp() public override {
        TestLens.setUp();

        IPermit2 permit2 = IPermit2(deployCode("../test-artifacts/Permit2.sol:Permit2"));

        GammaTradeMarket gammaTradeMarket =
            new GammaTradeMarket(predyPool, address(permit2), address(this), address(_predyPoolQuoter));

        _quoter = new GammaTradeMarketQuoter(gammaTradeMarket);

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
            1000,
            address(dutchOrderValidator),
            abi.encode(
                GeneralDutchOrderValidationData(
                    Constants.Q96, Bps.ONE + 100000, Bps.ONE + 200000, 101488915, block.timestamp, block.timestamp + 60
                )
            )
        );

        IFillerMarket.SettlementParams memory settlementData = _getUniSettlementData(0);

        IPredyPool.TradeResult memory tradeResult = _quoter.quoteExecuteOrder(order, settlementData);

        assertEq(tradeResult.payoff.perpEntryUpdate, 980);
        assertEq(tradeResult.payoff.sqrtEntryUpdate, -1782);
        assertEq(tradeResult.payoff.perpPayoff, 0);
        assertEq(tradeResult.payoff.sqrtPayoff, 0);
    }
}
