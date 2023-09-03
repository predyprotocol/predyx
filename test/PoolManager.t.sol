// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {SupplyHook} from "./mocks/SupplyHook.sol";
import {TradeHook} from "./mocks/TradeHook.sol";
import "../src/PoolManager.sol";

contract PoolManagerTest is Test {
    PoolManager public poolManager;
    MockERC20 currency0;
    MockERC20 currency1;
    SupplyHook supplyHook;
    TradeHook tradeHook;

    function setUp() public {
        currency0 = new MockERC20("currency0","currency0",18);

        currency1 = new MockERC20("currency1","currency1",18);

        currency0.mint(address(this), 1e10);
        currency1.mint(address(this), 1e10);

        poolManager = new PoolManager();
        poolManager.registerPair(address(0), address(currency1), address(currency0));

        supplyHook = new SupplyHook(poolManager);
        tradeHook = new TradeHook(poolManager);

        // TODO: swap
        currency0.transfer(address(tradeHook), 1000);
        currency1.transfer(address(tradeHook), 1000);
    }

    function testSupplyFailsIfPairNotFound() public {
        currency0.approve(address(poolManager), 1000);

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.PairNotFound.selector));
        poolManager.supply(0, false, 1000);
    }

    function testSupplySucceeds() public {
        currency0.approve(address(poolManager), 1000);
        poolManager.supply(1, false, 1000);
    }

    function testTradeSucceeds() public {
        currency0.approve(address(poolManager), 1000);
        currency1.approve(address(poolManager), 1000);

        poolManager.supply(1, false, 1000);
        poolManager.supply(1, true, 1000);

        tradeHook.trade(1, 1, 100, address(currency0), address(currency1));
    }
}
