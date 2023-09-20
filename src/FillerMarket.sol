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
import "./libraries/market/GeneralOrderLib.sol";
import "./libraries/math/Math.sol";
import "./libraries/Constants.sol";

/**
 * @notice Provides perps to retail traders
 */
contract FillerMarket is IFillerMarket, BaseHookCallback {
    using ResolvedOrderLib for ResolvedOrder;
    using GeneralOrderLib for GeneralOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;

    IPermit2 _permit2;
    ISwapRouter _swapRouter;
    address _quoteTokenAddress;

    struct SettlementParams {
        bytes path;
        uint256 amountOutMinimumOrInMaximum;
        address quoteTokenAddress;
        address baseTokenAddress;
        int256 fee;
    }

    struct UserPosition {
        uint256 vaultId;
        address owner;
        int256 marginCoveredByFiller;
    }

    mapping(uint256 => UserPosition) public userPositions;

    uint64 public positionCounts;

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
        (GeneralOrder memory generalOrder, ResolvedOrder memory resolvedOrder) = _resolve(order, _quoteTokenAddress);

        _verifyOrder(resolvedOrder);

        UserPosition storage userPosition;

        if (generalOrder.positionId == 0) {
            generalOrder.positionId = positionCounts;
            positionCounts++;

            userPosition = userPositions[generalOrder.positionId];

            userPosition.owner = generalOrder.info.trader;
        } else {
            userPosition = userPositions[generalOrder.positionId];

            if (generalOrder.info.trader != userPosition.owner) {
                revert IFillerMarket.SignerIsNotVaultOwner();
            }
        }

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                generalOrder.pairId,
                userPosition.vaultId,
                generalOrder.tradeAmount,
                generalOrder.tradeAmountSqrt,
                abi.encode(generalOrder.marginAmount)
            ),
            settlementData
        );

        userPosition.vaultId = tradeResult.vaultId;

        _validateGeneralOrder(generalOrder, tradeResult);

        if (generalOrder.marginAmount < 0) {
            IERC20(_quoteTokenAddress).transfer(generalOrder.info.trader, uint256(-generalOrder.marginAmount));
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

    function _resolve(SignedOrder memory order, address token)
        internal
        pure
        returns (GeneralOrder memory generalOrder, ResolvedOrder memory resolvedOrder)
    {
        return GeneralOrderLib.resolve(order, token);
    }

    // verifyOrder
    // limitPrice
    // triggerPrice

    function _verifyOrder(ResolvedOrder memory order) internal {
        order.validate();

        _permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(address(this)),
            order.info.trader,
            order.hash,
            GeneralOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    function _validateGeneralOrder(GeneralOrder memory generalOrder, IPredyPool.TradeResult memory tradeResult)
        internal
        pure
    {
        if (generalOrder.triggerPrice > 0) {
            uint256 twap = (tradeResult.sqrtTwap * tradeResult.sqrtTwap) >> Constants.RESOLUTION;

            if (generalOrder.tradeAmount > 0 && generalOrder.triggerPrice < twap) {
                revert TriggerNotMatched();
            }
            if (generalOrder.tradeAmount < 0 && generalOrder.triggerPrice > twap) {
                revert TriggerNotMatched();
            }
        }

        if (generalOrder.triggerPriceSqrt > 0) {
            if (generalOrder.tradeAmountSqrt > 0 && generalOrder.triggerPriceSqrt < tradeResult.sqrtTwap) {
                revert TriggerNotMatched();
            }
            if (generalOrder.tradeAmountSqrt < 0 && generalOrder.triggerPriceSqrt > tradeResult.sqrtTwap) {
                revert TriggerNotMatched();
            }
        }

        if (generalOrder.limitPrice > 0) {
            if (generalOrder.tradeAmount > 0 && generalOrder.limitPrice < uint256(-tradeResult.payoff.perpEntryUpdate))
            {
                revert PriceGreaterThanLimit();
            }

            if (generalOrder.tradeAmount < 0 && generalOrder.limitPrice > uint256(tradeResult.payoff.perpEntryUpdate)) {
                revert PriceLessThanLimit();
            }
        }

        if (generalOrder.limitPriceSqrt > 0) {
            if (
                generalOrder.tradeAmountSqrt > 0
                    && generalOrder.limitPriceSqrt < uint256(-tradeResult.payoff.sqrtEntryUpdate)
            ) {
                revert PriceGreaterThanLimit();
            }

            if (
                generalOrder.tradeAmountSqrt < 0
                    && generalOrder.limitPriceSqrt > uint256(tradeResult.payoff.sqrtEntryUpdate)
            ) {
                revert PriceLessThanLimit();
            }
        }
    }
}
