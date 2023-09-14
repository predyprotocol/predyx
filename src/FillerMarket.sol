// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPredyPool.sol";
import "./interfaces/IFillerMarket.sol";
import "./base/BaseHookCallback.sol";

/**
 * @notice Provides perps to retail traders
 */
contract FillerMarket is IFillerMarket, BaseHookCallback, IUniswapV3SwapCallback {
    struct SettlementParams {
        address quoteTokenAddress;
        address baseTokenAddress;
    }

    constructor(IPredyPool _predyPool) BaseHookCallback(_predyPool) {}

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        // require(allowedUniswapPools[msg.sender]);
        IUniswapV3Pool uniswapPool = IUniswapV3Pool(msg.sender);
        if (amount0Delta > 0) {
            TransferHelper.safeTransfer(uniswapPool.token0(), msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            TransferHelper.safeTransfer(uniswapPool.token1(), msg.sender, uint256(amount1Delta));
        }
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta)
        external
        override(BaseHookCallback)
    {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        if (baseAmountDelta > 0) {
            uint256 quoteAmount = uint256(baseAmountDelta);

            predyPool.take(settlemendParams.baseTokenAddress, address(this), uint256(baseAmountDelta));

            IERC20(settlemendParams.quoteTokenAddress).transfer(address(predyPool), quoteAmount);

            predyPool.settle(true);
        } else {
            uint256 quoteAmount = uint256(-baseAmountDelta);

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
    function trade(SignedOrder memory order, bytes memory settlementData)
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
