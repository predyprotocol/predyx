// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/PoolManager.sol";

contract PoolManagerTest is Test {
    PoolManager public poolManager;
    MockERC20 currency0;
    MockERC20 currency1;

    function setUp() public {
        currency0 = new MockERC20("currency0","currency0",18);

        currency1 = new MockERC20("currency1","currency1",18);

        poolManager = new PoolManager();
    }

    function lockAquired(
        IPoolManager.SignedOrder[] memory orders
    ) external {
        poolManager.updatePerpPosition(address(currency0), address(currency0), 100, 100);
    }

    function testIncrement() public {
        IPoolManager.SignedOrder[] memory data = new IPoolManager.SignedOrder[](0);
        uint256 a = 1;

        poolManager.lock(data);

        assertEq(a, 1);
    }
}
