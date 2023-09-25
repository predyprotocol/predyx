// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../pool/Setup.t.sol";
import "../../src/interfaces/ISettlement.sol";
import "../../src/GammaTradeMarket.sol";
import "../../src/settlements/UniswapSettlement.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";

contract TestMarket is TestPool {
    UniswapSettlement settlement;
    GammaTradeMarket fillerMarket;
    IPermit2 permit2;

    function setUp() public virtual override(TestPool) {
        TestPool.setUp();

        address swapRouter = deployCode(
            "../node_modules/@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol:SwapRouter",
            abi.encode(uniswapFactory, address(currency0))
        );

        permit2 = IPermit2(deployCode("../artifacts/Permit2.sol:Permit2"));

        settlement = new UniswapSettlement(predyPool, swapRouter);

        fillerMarket = new GammaTradeMarket(predyPool, address(currency1), address(permit2));

        currency0.approve(address(permit2), type(uint256).max);
        currency1.approve(address(permit2), type(uint256).max);

        currency0.approve(address(fillerMarket), type(uint256).max);
        currency1.approve(address(fillerMarket), type(uint256).max);
    }
}
