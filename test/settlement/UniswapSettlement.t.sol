// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../../src/settlements/UniswapSettlement.sol";

contract TestUniswapSettlement is TestSettlementSetup {
    UniswapSettlement _uniswapSettlement;

    function setUp() public override {
        TestSettlementSetup.setUp();

        _uniswapSettlement = new UniswapSettlement(mockPredyPool, swapRouter, quoterV2, filler);
    }

    function testPredySettlementCallback() public {
        (int256 a, int256 b) = mockPredyPool.exec(
            _uniswapSettlement.getSettlementParams(
                abi.encodePacked(address(currency1), uint24(500), address(currency0)),
                0,
                address(currency0),
                address(currency1),
                0
            ),
            100
        );

        assertEq(a, 98);
        assertEq(b, -100);
        assertEq(currency0.balanceOf(address(_uniswapSettlement)), 0);
        assertEq(currency1.balanceOf(address(_uniswapSettlement)), 0);
    }
}
