// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../../src/settlements/UniswapSettlement2.sol";
import {Constants} from "../../src/libraries/Constants.sol";

contract TestUniswapSettlement2 is TestSettlementSetup {
    UniswapSettlement2 _uniswapSettlement2;

    function setUp() public override {
        TestSettlementSetup.setUp();

        _uniswapSettlement2 = new UniswapSettlement2(mockPredyPool, swapRouter, quoterV2, filler);

        vm.startPrank(filler);
        currency0.approve(address(_uniswapSettlement2), type(uint256).max);
        currency1.approve(address(_uniswapSettlement2), type(uint256).max);
        vm.stopPrank();
    }

    function testPredySettlementCallback() public {
        (int256 a, int256 b) = mockPredyPool.exec(
            _uniswapSettlement2.getSettlementParams(
                abi.encodePacked(address(currency1), uint24(500), address(currency0)),
                0,
                address(currency0),
                address(currency1),
                Constants.Q96
            ),
            100
        );

        assertEq(a, 100);
        assertEq(b, -100);
        assertEq(currency0.balanceOf(address(_uniswapSettlement2)), 0);
        assertEq(currency1.balanceOf(address(_uniswapSettlement2)), 0);
    }
}
