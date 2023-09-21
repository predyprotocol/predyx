// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPredyPool.sol";
import "./interfaces/IFillerMarket.sol";
import "./base/BaseMarket.sol";
import "./libraries/market/Permit2Lib.sol";
import "./libraries/market/ResolvedOrder.sol";
import "./libraries/market/GeneralOrderLib.sol";
import "./libraries/math/Math.sol";

/**
 * @notice Provides perps to retail traders
 */
contract PerpMarket is IFillerMarket, BaseMarket {
    using ResolvedOrderLib for ResolvedOrder;
    using GeneralOrderLib for GeneralOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;

    IPermit2 _permit2;
    address _quoteTokenAddress;

    struct UserPosition {
        address owner;
        int256 marginCoveredByFiller;
    }

    mapping(uint256 vaultId => UserPosition) public userPositions;

    constructor(IPredyPool _predyPool, address swapRouterAddress, address quoteTokenAddress, address permit2Address)
        BaseMarket(_predyPool, swapRouterAddress)
    {
        _quoteTokenAddress = quoteTokenAddress;
        _permit2 = IPermit2(permit2Address);
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseMarket) {
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
        IPredyPool.TradeResult memory tradeResult,
        int256 marginAmount
    ) external override(BaseMarket) {
        UserPosition memory userPosition = userPositions[tradeParams.vaultId];

        if (tradeResult.minDeposit == 0 && marginAmount > 0) {
            _predyPool.take(true, address(this), uint256(marginAmount));

            IERC20(_quoteTokenAddress).transfer(
                userPosition.owner, uint256(marginAmount - userPosition.marginCoveredByFiller)
            );
        }
    }

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
        (GeneralOrder memory generalOrder, ResolvedOrder memory resolvedOrder) =
            GeneralOrderLib.resolve(order, _quoteTokenAddress);

        _verifyOrder(resolvedOrder);

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                generalOrder.pairId,
                generalOrder.positionId,
                generalOrder.tradeAmount,
                generalOrder.tradeAmountSqrt,
                abi.encode(generalOrder.marginAmount)
            ),
            settlementData
        );

        if (generalOrder.positionId == 0) {
            userPositions[tradeResult.vaultId].owner = generalOrder.info.trader;
        } else {
            if (generalOrder.info.trader != userPositions[tradeResult.vaultId].owner) {
                revert IFillerMarket.SignerIsNotVaultOwner();
            }
        }

        generalOrder.validateGeneralOrder(tradeResult);

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
    function execLiquidationCall(uint256 positionId, bytes memory settlementData) external {
        // TODO: liquidation call
        // check vault is danger
        //
    }

    function depositToFillerPool(uint256 depositAmount) external {
        IERC20(_quoteTokenAddress).transferFrom(msg.sender, address(this), depositAmount);
    }

    function withdrawFromFillerPool(uint256 withdrawAmount) external {
        IERC20(_quoteTokenAddress).transfer(msg.sender, withdrawAmount);
    }

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
}
