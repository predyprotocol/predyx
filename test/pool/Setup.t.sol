// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/PredyPool.sol";
import "../mocks/MockERC20.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract TestPool is Test {
    PredyPool predyPool;

    MockERC20 currency0;
    MockERC20 currency1;

    IUniswapV3Pool internal uniswapPool;

    uint256 internal constant RISK_RATIO = 109544511;

    address uniswapFactory;

    function setUp() public virtual {
        currency0 = new MockERC20("currency0","currency0",18);
        currency1 = new MockERC20("currency1","currency1",18);
        currency0.mint(address(this), type(uint128).max);
        currency1.mint(address(this), type(uint128).max);

        uniswapFactory =
            deployCode("../node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol:UniswapV3Factory");

        uniswapPool =
            IUniswapV3Pool(IUniswapV3Factory(uniswapFactory).createPool(address(currency0), address(currency1), 500));

        uniswapPool.initialize(2 ** 96);

        IUniswapV3PoolActions(address(uniswapPool)).increaseObservationCardinalityNext(180);

        currency0.approve(address(uniswapPool), type(uint256).max);
        currency1.approve(address(uniswapPool), type(uint256).max);

        uniswapPool.mint(address(this), -2000, 2000, 1e18, bytes(""));

        predyPool = new PredyPool(uniswapFactory);

        currency0.approve(address(predyPool), type(uint256).max);
        currency1.approve(address(predyPool), type(uint256).max);
    }

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external {
        if (amount0 > 0) {
            TransferHelper.safeTransfer(IUniswapV3Pool(msg.sender).token0(), msg.sender, amount0);
        }
        if (amount1 > 0) {
            TransferHelper.safeTransfer(IUniswapV3Pool(msg.sender).token1(), msg.sender, amount1);
        }
    }

    function registerPair(address marginId) public {
        InterestRateModel.IRMParams memory irmParams = InterestRateModel.IRMParams(1e16, 9 * 1e17, 5 * 1e17, 1e18);

        predyPool.registerPair(
            AddPairLogic.AddPairParams(
                marginId,
                address(this),
                address(uniswapPool),
                0,
                Perp.AssetRiskParams(RISK_RATIO, 1000, 500),
                irmParams,
                irmParams
            )
        );
    }
}
