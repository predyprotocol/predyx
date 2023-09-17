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
    address _quoteTokenAddress;

    struct SettlementParams {
        bytes path;
        uint256 amountOutMinimumOrInMaximum;
        address quoteTokenAddress;
        address baseTokenAddress;
    }

    struct UserPosition {
        uint256 vaultId;
        int256 marginCoveredByFiller;
    }

    mapping(uint256 => UserPosition) public userPositions;

    constructor(IPredyPool _predyPool, address _swapRouter, address __quoteTokenAddress) BaseHookCallback(_predyPool) {
        swapRouter = ISwapRouter(_swapRouter);
        _quoteTokenAddress = __quoteTokenAddress;
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta)
        external
        override(BaseHookCallback)
    {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        if (baseAmountDelta > 0) {
            predyPool.take(false, address(this), uint256(baseAmountDelta));

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
        } else {
            IERC20(settlemendParams.quoteTokenAddress).approve(
                address(swapRouter), settlemendParams.amountOutMinimumOrInMaximum
            );

            predyPool.take(true, address(this), settlemendParams.amountOutMinimumOrInMaximum);

            uint256 quoteAmount = swapRouter.exactOutput(
                ISwapRouter.ExactOutputParams(
                    settlemendParams.path,
                    address(this),
                    block.timestamp,
                    uint256(-baseAmountDelta),
                    settlemendParams.amountOutMinimumOrInMaximum
                )
            );

            IERC20(settlemendParams.quoteTokenAddress).transfer(
                address(predyPool), settlemendParams.amountOutMinimumOrInMaximum - quoteAmount
            );

            IERC20(settlemendParams.baseTokenAddress).transfer(address(predyPool), uint256(-baseAmountDelta));
        }
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallback) {
        int256 marginAmountUpdate = abi.decode(tradeParams.extraData, (int256));

        int256 finalMarginAmountUpdate =
            marginAmountUpdate + tradeResult.minDeposit - userPositions[tradeParams.vaultId].marginCoveredByFiller;

        userPositions[tradeParams.vaultId].marginCoveredByFiller = tradeResult.minDeposit;

        if (finalMarginAmountUpdate > 0) {
            IERC20(_quoteTokenAddress).transfer(address(predyPool), uint256(finalMarginAmountUpdate));
        } else if (finalMarginAmountUpdate < 0) {
            predyPool.take(true, address(this), uint256(-finalMarginAmountUpdate));
        }
    }

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
        if (order.order.marginAmount > 0) {
            IERC20(_quoteTokenAddress).transferFrom(msg.sender, address(this), uint256(order.order.marginAmount));
        }

        UserPosition storage userPosition = userPositions[order.order.positionId];

        tradeResult = predyPool.trade(
            IPredyPool.TradeParams(
                order.order.pairId,
                userPosition.vaultId,
                order.order.tradeAmount,
                order.order.tradeAmountSqrt,
                abi.encode(order.order.marginAmount)
            ),
            settlementData
        );

        userPosition.vaultId = tradeResult.vaultId;

        // TODO: check limitPrice and limitPriceSqrt
        if (order.order.tradeAmount > 0 && order.order.limitPrice < uint256(-tradeResult.payoff.perpEntryUpdate)) {
            revert PriceGreaterThanLimit();
        }

        if (order.order.tradeAmount < 0 && order.order.limitPrice > uint256(tradeResult.payoff.perpEntryUpdate)) {
            revert PriceLessThanLimit();
        }

        return tradeResult;
    }

    function execLiquidationCall(uint256 positionId, bytes memory settlementData) external {}

    function depositToFillerPool(uint256 depositAmount) external {
        IERC20(_quoteTokenAddress).transferFrom(msg.sender, address(this), depositAmount);
    }

    function withdrawFromFillerPool(uint256 withdrawAmount) external {}

    function getPositionStatus(uint256 positionId) external {}
}
