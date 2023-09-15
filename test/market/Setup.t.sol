// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pool/Setup.t.sol";
import "../../src/FillerMarket.sol";

contract TestMarket is TestPool {
    FillerMarket fillerMarket;

    function setUp() public virtual override(TestPool) {
        TestPool.setUp();

        address swapRouter = deployCode(
            "../node_modules/@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol:SwapRouter",
            abi.encode(uniswapFactory, address(currency0))
        );

        fillerMarket = new FillerMarket(predyPool, swapRouter);
    }
}
