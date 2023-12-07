// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../../src/lens/SpotMarketQuoter.sol";
import "../../src/settlements/RevertSettlement.sol";
import "../../src/markets/validators/LimitOrderValidator.sol";
import {OrderInfo} from "../../src/libraries/orders/OrderInfoLib.sol";
import "../../src/settlements/UniswapSettlement.sol";
import "../../src/markets/spot/SpotExclusiveLimitOrderValidator.sol";

contract TestSpotMarketQuoter is TestLens {
    SpotMarketQuoter _quoter;

    SpotExclusiveLimitOrderValidator spotExclusiveLimitOrderValidator;

    address from;

    function setUp() public override {
        TestLens.setUp();

        _quoter = new SpotMarketQuoter();
        spotExclusiveLimitOrderValidator = new SpotExclusiveLimitOrderValidator();

        from = vm.addr(1);
    }

    function testQuoteExecuteOrderFails() public {
        SpotOrder memory order = SpotOrder(
            OrderInfo(address(0), from, 0, block.timestamp + 100),
            address(currency1),
            address(currency0),
            1000,
            1100,
            address(spotExclusiveLimitOrderValidator),
            abi.encode(SpotExclusiveLimitOrderValidationData(address(this), 1000))
        );

        ISettlement.SettlementData memory settlementData = uniswapSettlement.getSettlementParams(
            abi.encodePacked(address(currency0), uint24(500), address(currency1)),
            0,
            address(currency1),
            address(currency0),
            0
        );

        vm.expectRevert(SpotExclusiveLimitOrderValidator.PriceGreaterThanLimit.selector);
        _quoter.quoteExecuteOrder(order, settlementData);
    }

    function testQuoteExecuteOrderSucceeds() public {
        SpotOrder memory order = SpotOrder(
            OrderInfo(address(0), from, 0, block.timestamp + 100),
            address(currency1),
            address(currency0),
            1000,
            1100,
            address(spotExclusiveLimitOrderValidator),
            abi.encode(SpotExclusiveLimitOrderValidationData(address(this), 1002))
        );

        ISettlement.SettlementData memory settlementData = uniswapSettlement.getSettlementParams(
            abi.encodePacked(address(currency0), uint24(500), address(currency1)),
            0,
            address(currency1),
            address(currency0),
            0
        );

        assertEq(_quoter.quoteExecuteOrder(order, settlementData), -1002);
    }
}
