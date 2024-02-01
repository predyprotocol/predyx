// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../../src/lens/SpotMarketQuoter.sol";
import "../../src/markets/validators/LimitOrderValidator.sol";
import "../../src/markets/spot/SpotMarketV1.sol";
import {OrderInfo} from "../../src/libraries/orders/OrderInfoLib.sol";
import "../../src/settlements/UniswapSettlement.sol";
import "../../src/markets/spot/SpotExclusiveLimitOrderValidator.sol";

contract TestSpotMarketQuoter is TestLens {
    SpotMarketQuoter _quoter;
    SpotMarketV1 _spotMarket;
    SpotExclusiveLimitOrderValidator _spotExclusiveLimitOrderValidator;
    address _from;

    function setUp() public override {
        TestLens.setUp();

        IPermit2 permit2 = IPermit2(deployCode("../test-artifacts/Permit2.sol:Permit2"));

        _spotMarket = new SpotMarketV1(address(permit2));
        _spotMarket.updateWhitelistSettlement(address(uniswapSettlement), true);

        _quoter = new SpotMarketQuoter(_spotMarket);
        _spotExclusiveLimitOrderValidator = new SpotExclusiveLimitOrderValidator();

        _from = vm.addr(1);
    }

    function testQuoteExecuteOrderFails() public {
        SpotOrder memory order = SpotOrder(
            OrderInfo(address(0), _from, 0, block.timestamp + 100),
            address(currency1),
            address(currency0),
            1000,
            1100,
            address(_spotExclusiveLimitOrderValidator),
            abi.encode(SpotExclusiveLimitOrderValidationData(address(this), 1000))
        );

        IFillerMarket.SettlementParamsItem[] memory items = new IFillerMarket.SettlementParamsItem[](1);

        items[0] = IFillerMarket.SettlementParamsItem(
            address(uniswapSettlement), abi.encodePacked(address(currency0), uint24(500), address(currency1)), 0, 0
        );

        IFillerMarket.SettlementParams memory settlementData = IFillerMarket.SettlementParams(0, 0, items);

        vm.expectRevert(SpotExclusiveLimitOrderValidator.PriceGreaterThanLimit.selector);
        _quoter.quoteExecuteOrder(order, settlementData);
    }

    function testQuoteExecuteOrderSucceedsWithBuying() public {
        SpotOrder memory order = SpotOrder(
            OrderInfo(address(0), _from, 0, block.timestamp + 100),
            address(currency1),
            address(currency0),
            1000,
            1100,
            address(_spotExclusiveLimitOrderValidator),
            abi.encode(SpotExclusiveLimitOrderValidationData(address(this), 1012))
        );

        // with settlement contract
        assertEq(_quoter.quoteExecuteOrder(order, _getUniSettlementData(0)), -1002);

        // with fee
        assertEq(_quoter.quoteExecuteOrder(order, _getUniSettlementData(0, 0, 10)), -1012);

        // with direct
        {
            IFillerMarket.SettlementParamsItem[] memory items = new IFillerMarket.SettlementParamsItem[](1);

            items[0] = IFillerMarket.SettlementParamsItem(address(0), bytes(""), 0, 0);

            assertEq(_quoter.quoteExecuteOrder(order, IFillerMarket.SettlementParams(Constants.Q96, 0, items)), -1000);
        }

        // with price
        assertEq(_quoter.quoteExecuteOrder(order, _getUniSettlementData(0, Constants.Q96, 0)), -1000);
    }

    function testQuoteExecuteOrderSucceedsWithSelling() public {
        SpotOrder memory order = SpotOrder(
            OrderInfo(address(0), _from, 0, block.timestamp + 100),
            address(currency1),
            address(currency0),
            -1000,
            1100,
            address(_spotExclusiveLimitOrderValidator),
            abi.encode(SpotExclusiveLimitOrderValidationData(address(this), 988))
        );

        // with settlement contract
        assertEq(_quoter.quoteExecuteOrder(order, _getUniSettlementData(1200)), 998);

        // with fee
        assertEq(_quoter.quoteExecuteOrder(order, _getUniSettlementData(1200, 0, 10)), 988);

        // with direct
        {
            IFillerMarket.SettlementParamsItem[] memory items = new IFillerMarket.SettlementParamsItem[](1);

            items[0] = IFillerMarket.SettlementParamsItem(address(0), bytes(""), 1200, 0);

            assertEq(_quoter.quoteExecuteOrder(order, IFillerMarket.SettlementParams(Constants.Q96, 0, items)), 1000);
        }

        // with price
        assertEq(_quoter.quoteExecuteOrder(order, _getUniSettlementData(1200, Constants.Q96, 0)), 1000);
    }
}
