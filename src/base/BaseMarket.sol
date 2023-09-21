// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IPredyPool.sol";
import "./BaseHookCallback.sol";
import "../libraries/math/Math.sol";

/**
 * @notice Base market contract
 */
abstract contract BaseMarket is BaseHookCallback {
    using Math for uint256;

    ISwapRouter _swapRouter;

    struct SettlementParams {
        bytes path;
        uint256 amountOutMinimumOrInMaximum;
        address quoteTokenAddress;
        address baseTokenAddress;
        int256 fee;
    }

    constructor(IPredyPool _predyPool, address swapRouterAddress) BaseHookCallback(_predyPool) {
        _swapRouter = ISwapRouter(swapRouterAddress);
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta)
        external
        override(BaseHookCallback)
    {
        SettlementParams memory settlementParams = abi.decode(settlementData, (SettlementParams));

        if (baseAmountDelta > 0) {
            _predyPool.take(false, address(this), uint256(baseAmountDelta));

            IERC20(settlementParams.baseTokenAddress).approve(address(_swapRouter), uint256(baseAmountDelta));

            uint256 quoteAmount = _swapRouter.exactInput(
                ISwapRouter.ExactInputParams(
                    settlementParams.path,
                    address(this),
                    block.timestamp,
                    uint256(baseAmountDelta),
                    settlementParams.amountOutMinimumOrInMaximum
                )
            );

            IERC20(settlementParams.quoteTokenAddress).transfer(
                address(_predyPool), quoteAmount.addDelta(settlementParams.fee)
            );
        } else {
            IERC20(settlementParams.quoteTokenAddress).approve(
                address(_swapRouter), settlementParams.amountOutMinimumOrInMaximum
            );

            _predyPool.take(true, address(this), settlementParams.amountOutMinimumOrInMaximum);

            uint256 quoteAmount = _swapRouter.exactOutput(
                ISwapRouter.ExactOutputParams(
                    settlementParams.path,
                    address(this),
                    block.timestamp,
                    uint256(-baseAmountDelta),
                    settlementParams.amountOutMinimumOrInMaximum
                )
            );

            IERC20(settlementParams.quoteTokenAddress).transfer(
                address(_predyPool),
                settlementParams.amountOutMinimumOrInMaximum - quoteAmount.addDelta(settlementParams.fee)
            );

            IERC20(settlementParams.baseTokenAddress).transfer(address(_predyPool), uint256(-baseAmountDelta));
        }
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external virtual override(BaseHookCallback) {}

    function predyLiquidationCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult,
        int256 marginAmount
    ) external virtual override(BaseHookCallback) {}
}
