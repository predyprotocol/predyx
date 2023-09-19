// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPredyPool.sol";
import "./interfaces/IFillerMarket.sol";
import "./base/BaseHookCallback.sol";
import "./libraries/market/Permit2Lib.sol";
import "./libraries/market/ResolvedOrder.sol";
import "./libraries/market/MarketOrderLib.sol";

/**
 * @notice Provides perps to retail traders
 */
contract FillerMarket is IFillerMarket, BaseHookCallback {
    using MarketOrderLib for MarketOrder;
    using Permit2Lib for ResolvedOrder;

    IPermit2 _permit2;
    ISwapRouter _swapRouter;
    address _quoteTokenAddress;

    struct SettlementParams {
        bytes path;
        uint256 amountOutMinimumOrInMaximum;
        address quoteTokenAddress;
        address baseTokenAddress;
    }

    struct UserPosition {
        uint256 vaultId;
        address owner;
        int256 marginCoveredByFiller;
    }

    mapping(uint256 => UserPosition) public userPositions;

    uint256 positionCounts;

    constructor(IPredyPool _predyPool, address swapRouterAddress, address quoteTokenAddress, address permit2Address)
        BaseHookCallback(_predyPool)
    {
        _swapRouter = ISwapRouter(swapRouterAddress);
        _quoteTokenAddress = quoteTokenAddress;
        _permit2 = IPermit2(permit2Address);

        positionCounts = 1;
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta)
        external
        override(BaseHookCallback)
    {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        if (baseAmountDelta > 0) {
            _predyPool.take(false, address(this), uint256(baseAmountDelta));

            IERC20(settlemendParams.baseTokenAddress).approve(address(_swapRouter), uint256(baseAmountDelta));

            uint256 quoteAmount = _swapRouter.exactInput(
                ISwapRouter.ExactInputParams(
                    settlemendParams.path,
                    address(this),
                    block.timestamp,
                    uint256(baseAmountDelta),
                    settlemendParams.amountOutMinimumOrInMaximum
                )
            );

            IERC20(settlemendParams.quoteTokenAddress).transfer(address(_predyPool), quoteAmount);
        } else {
            IERC20(settlemendParams.quoteTokenAddress).approve(
                address(_swapRouter), settlemendParams.amountOutMinimumOrInMaximum
            );

            _predyPool.take(true, address(this), settlemendParams.amountOutMinimumOrInMaximum);

            uint256 quoteAmount = _swapRouter.exactOutput(
                ISwapRouter.ExactOutputParams(
                    settlemendParams.path,
                    address(this),
                    block.timestamp,
                    uint256(-baseAmountDelta),
                    settlemendParams.amountOutMinimumOrInMaximum
                )
            );

            IERC20(settlemendParams.quoteTokenAddress).transfer(
                address(_predyPool), settlemendParams.amountOutMinimumOrInMaximum - quoteAmount
            );

            IERC20(settlemendParams.baseTokenAddress).transfer(address(_predyPool), uint256(-baseAmountDelta));
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
            IERC20(_quoteTokenAddress).transfer(address(_predyPool), uint256(finalMarginAmountUpdate));
        } else if (finalMarginAmountUpdate < 0) {
            _predyPool.take(true, address(this), uint256(-finalMarginAmountUpdate));
        }
    }

    function predyLiquidationCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallback) {}

    /**
     * @notice Verifies signature of the order and executes trade
     * @param order The order signed by trader
     * @param settlementData The route of settlement created by filler
     * @dev Fillers call this function
     */
    function executeOrder(SignedOrder memory order, bytes memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        (MarketOrder memory marketOrder, ResolvedOrder memory resolvedOrder) = _resolve(order);

        _verifyOrder(resolvedOrder);

        UserPosition storage userPosition;

        if (marketOrder.positionId == 0) {
            marketOrder.positionId = positionCounts;
            positionCounts++;

            userPosition = userPositions[marketOrder.positionId];

            userPosition.owner = marketOrder.info.trader;
        } else {
            userPosition = userPositions[marketOrder.positionId];

            if (marketOrder.info.trader != userPosition.owner) {
                revert IFillerMarket.SignerIsNotVaultOwner();
            }
        }

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                marketOrder.pairId,
                userPosition.vaultId,
                marketOrder.tradeAmount,
                marketOrder.tradeAmountSqrt,
                abi.encode(marketOrder.marginAmount)
            ),
            settlementData
        );

        userPosition.vaultId = tradeResult.vaultId;

        // TODO: check limitPrice and limitPriceSqrt
        if (marketOrder.tradeAmount > 0 && marketOrder.limitPrice < uint256(-tradeResult.payoff.perpEntryUpdate)) {
            revert PriceGreaterThanLimit();
        }

        if (marketOrder.tradeAmount < 0 && marketOrder.limitPrice > uint256(tradeResult.payoff.perpEntryUpdate)) {
            revert PriceLessThanLimit();
        }

        if (marketOrder.marginAmount < 0) {
            IERC20(_quoteTokenAddress).transfer(marketOrder.info.trader, uint256(-marketOrder.marginAmount));
        }

        return tradeResult;
    }

    /**
     * @notice Executes liquidation call for the position
     * @param positionId The id of position
     * @param settlementData The route of settlement created by liquidator
     */
    function execLiquidationCall(uint256 positionId, bytes memory settlementData) external {}

    function depositToFillerPool(uint256 depositAmount) external {
        IERC20(_quoteTokenAddress).transferFrom(msg.sender, address(this), depositAmount);
    }

    function withdrawFromFillerPool(uint256 withdrawAmount) external {
        IERC20(_quoteTokenAddress).transfer(msg.sender, withdrawAmount);
    }

    function getPositionStatus(uint256 positionId) external {}

    function _resolve(SignedOrder memory order)
        internal
        view
        returns (MarketOrder memory marketOrder, ResolvedOrder memory)
    {
        return MarketOrderLib.resolve(order, _quoteTokenAddress);
    }

    function _verifyOrder(ResolvedOrder memory order) internal {
        _permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(address(this)),
            order.info.trader,
            order.hash,
            MarketOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }
}
