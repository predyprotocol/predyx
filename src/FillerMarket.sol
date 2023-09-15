// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPredyPool.sol";
import "./interfaces/IFillerMarket.sol";
import "./base/BaseHookCallback.sol";

/**
 * @notice Provides perps to retail traders
 */
contract FillerMarket is IFillerMarket, BaseHookCallback {
    ISwapRouter swapRouter;

    struct SettlementParams {
        bytes path;
        uint256 amountOutMinimumOrInMaximum;
        address quoteTokenAddress;
        address baseTokenAddress;
    }

    constructor(IPredyPool _predyPool, address _swapRouter) BaseHookCallback(_predyPool) {
        swapRouter = ISwapRouter(_swapRouter);
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta)
        external
        override(BaseHookCallback)
    {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        if (baseAmountDelta > 0) {
            predyPool.take(settlemendParams.baseTokenAddress, address(this), uint256(baseAmountDelta));

            IERC20(settlemendParams.baseTokenAddress).approve(address(swapRouter), uint256(baseAmountDelta));

            uint256 quoteAmount = swapRouter.exactInput(
                ISwapRouter.ExactInputParams(
                    settlemendParams.path,
                    address(this),
                    block.timestamp,
                    uint256(baseAmountDelta),
                    settlemendParams.amountOutMinimumOrInMaximum
                )
            );

            IERC20(settlemendParams.quoteTokenAddress).transfer(address(predyPool), quoteAmount);

            predyPool.settle(true);
        } else {
            IERC20(settlemendParams.quoteTokenAddress).approve(address(swapRouter), settlemendParams.amountOutMinimumOrInMaximum);

            uint256 quoteAmount = swapRouter.exactOutput(
                ISwapRouter.ExactOutputParams(
                    settlemendParams.path,
                    address(this),
                    block.timestamp,
                    uint256(-baseAmountDelta),
                    settlemendParams.amountOutMinimumOrInMaximum
                )
            );

            predyPool.take(settlemendParams.quoteTokenAddress, address(this), quoteAmount);

            IERC20(settlemendParams.baseTokenAddress).transfer(address(predyPool), uint256(-baseAmountDelta));

            predyPool.settle(false);
        }
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallback) {}

    function predyLiquidationCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallback) {}

    /**
     * @notice Verifies signature of the order and executes trade
     */
    function executeOrder(SignedOrder memory order, bytes memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        return predyPool.trade(
            order.order.pairId,
            IPredyPool.TradeParams(order.order.pairId, 1, order.order.tradeAmount, order.order.tradeAmountSqrt, ""),
            settlementData
        );
    }

    function execLiquidationCall(uint256 positionId, bytes memory settlementData) external {}

    function depositToFillerPool(uint256 depositAmount) external {}

    function withdrawFromFillerPool(uint256 withdrawAmount) external {}

    function getPositionStatus(uint256 positionId) external {}
}
