// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3PoolActions} from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import "../mocks/MockERC20.sol";
import "../../src/interfaces/ILendingPool.sol";
import "../../src/interfaces/ISettlement.sol";

contract MockPredyPool is ILendingPool {
    ERC20 internal quoteToken;
    ERC20 internal baseToken;
    uint256 internal quoteBalance;
    uint256 internal baseBalance;

    constructor(address currency0, address currency1) {
        quoteToken = ERC20(currency0);
        baseToken = ERC20(currency1);
    }

    function _initialize() internal {
        quoteBalance = quoteToken.balanceOf(address(this));
        baseBalance = baseToken.balanceOf(address(this));
    }

    function exec(ISettlement.SettlementData memory settlementData, int256 baseAmountDelta)
        external
        returns (int256, int256)
    {
        _initialize();

        ISettlement(settlementData.settlementContractAddress).predySettlementCallback(
            settlementData.encodedData, baseAmountDelta
        );

        return _finalize();
    }

    function take(bool isQuoteAsset, address to, uint256 amount) external override(ILendingPool) {
        if (isQuoteAsset) {
            quoteToken.transfer(to, amount);
        } else {
            baseToken.transfer(to, amount);
        }
    }

    function _finalize() internal view returns (int256, int256) {
        return (
            int256(quoteToken.balanceOf(address(this))) - int256(quoteBalance),
            int256(baseToken.balanceOf(address(this))) - int256(baseBalance)
        );
    }
}

contract TestSettlementSetup is Test {
    MockERC20 currency0;
    MockERC20 currency1;

    IUniswapV3Pool internal uniswapPool;

    address uniswapFactory;

    address swapRouter;

    address quoterV2;

    MockPredyPool mockPredyPool;

    address filler;

    function setUp() public virtual {
        currency0 = new MockERC20("currency0", "currency0", 18);
        currency1 = new MockERC20("currency1", "currency1", 18);

        if (address(currency0) < address(currency1)) {
            (currency0, currency1) = (currency1, currency0);
        }

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

        uniswapPool.mint(address(this), -4000, 4000, 1e18, bytes(""));

        swapRouter = deployCode(
            "../node_modules/@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol:SwapRouter",
            abi.encode(uniswapFactory, address(currency0))
        );

        quoterV2 = deployCode(
            "../node_modules/@uniswap/v3-periphery/artifacts/contracts/lens/QuoterV2.sol:QuoterV2",
            abi.encode(uniswapFactory, address(currency0))
        );

        mockPredyPool = new MockPredyPool(address(currency0), address(currency1));

        filler = vm.addr(1);

        currency0.mint(address(mockPredyPool), 1e6);
        currency1.mint(address(mockPredyPool), 1e6);

        currency0.mint(filler, 1e6);
        currency1.mint(filler, 1e6);
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

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (amount0Delta > 0) {
            TransferHelper.safeTransfer(IUniswapV3Pool(msg.sender).token0(), msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            TransferHelper.safeTransfer(IUniswapV3Pool(msg.sender).token1(), msg.sender, uint256(amount1Delta));
        }
    }
}
