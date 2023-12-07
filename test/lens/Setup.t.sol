// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "../../src/lens/PredyPoolQuoter.sol";
import "../../src/settlements/RevertSettlement.sol";
import "../../src/settlements/UniswapSettlement.sol";
import "../pool/Setup.t.sol";

contract TestLens is TestPool {
    UniswapSettlement uniswapSettlement;

    function setUp() public virtual override(TestPool) {
        TestPool.setUp();

        registerPair(address(currency1), address(0));

        predyPool.supply(1, true, 1e10);
        predyPool.supply(1, false, 1e10);

        address swapRouter = deployCode(
            "../node_modules/@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol:SwapRouter",
            abi.encode(uniswapFactory, address(currency0))
        );
        address quoterV2 = deployCode(
            "../node_modules/@uniswap/v3-periphery/artifacts/contracts/lens/QuoterV2.sol:QuoterV2",
            abi.encode(uniswapFactory, address(currency0))
        );

        uniswapSettlement = new UniswapSettlement(predyPool, swapRouter, quoterV2, address(this));
    }
}
