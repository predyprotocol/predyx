// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPredyPool.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/IFillerMarket.sol";
import "./interfaces/IOrderValidator.sol";
import "./base/BaseHookCallback.sol";
import "./libraries/orders/Permit2Lib.sol";
import "./libraries/orders/ResolvedOrder.sol";
import "./libraries/orders/GammaOrder.sol";
import "./libraries/math/Math.sol";

/**
 * @notice Gamma trade market contract
 */
contract GammaTradeMarket is IFillerMarket, BaseHookCallback {
    using ResolvedOrderLib for ResolvedOrder;
    using GammaOrderLib for GammaOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;

    IPermit2 _permit2;

    mapping(uint256 vaultId => address) public userPositions;

    event Traded(address trader, uint256 vaultId);

    constructor(IPredyPool _predyPool, address permit2Address) BaseHookCallback(_predyPool) {
        _permit2 = IPermit2(permit2Address);
    }

    function predyTradeAfterCallback(IPredyPool.TradeParams memory tradeParams, IPredyPool.TradeResult memory)
        external
        override(BaseHookCallback)
        onlyPredyPool
    {
        int256 marginAmountUpdate = abi.decode(tradeParams.extraData, (int256));

        if (marginAmountUpdate > 0) {
            TransferHelper.safeTransfer(
                _getQuoteTokenAddress(tradeParams.pairId), address(_predyPool), uint256(marginAmountUpdate)
            );
        } else if (marginAmountUpdate < 0) {
            ILendingPool(address(_predyPool)).take(true, address(this), uint256(-marginAmountUpdate));
        }
    }

    /**
     * @notice Verifies signature of the order and executes trade
     * @param order The order signed by trader
     * @param settlementData The route of settlement created by filler
     * @dev Fillers call this function
     */
    function executeOrder(SignedOrder memory order, ISettlement.SettlementData memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        GammaOrder memory gammaOrder = abi.decode(order.order, (GammaOrder));
        ResolvedOrder memory resolvedOrder = GammaOrderLib.resolve(gammaOrder, order.sig);

        require(_quoteTokenMap[gammaOrder.pairId] != address(0));
        // TODO: check gammaOrder.entryTokenAddress and _quoteTokenMap[gammaOrder.pairId]
        require(gammaOrder.entryTokenAddress == _quoteTokenMap[gammaOrder.pairId]);

        _verifyOrder(resolvedOrder);

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                gammaOrder.pairId,
                gammaOrder.positionId,
                gammaOrder.tradeAmount,
                gammaOrder.tradeAmountSqrt,
                abi.encode(gammaOrder.marginAmount)
            ),
            settlementData
        );

        if (gammaOrder.positionId == 0) {
            userPositions[tradeResult.vaultId] = gammaOrder.info.trader;

            _predyPool.updateRecepient(tradeResult.vaultId, gammaOrder.info.trader);
        } else {
            if (gammaOrder.info.trader != userPositions[tradeResult.vaultId]) {
                revert IFillerMarket.SignerIsNotVaultOwner();
            }
        }

        // TODO: should have whote list for validatorAddress?
        IOrderValidator(gammaOrder.validatorAddress).validate(gammaOrder, tradeResult);

        if (gammaOrder.marginAmount < 0) {
            TransferHelper.safeTransfer(
                _quoteTokenMap[gammaOrder.pairId], gammaOrder.info.trader, uint256(-gammaOrder.marginAmount)
            );
        }

        emit Traded(gammaOrder.info.trader, tradeResult.vaultId);

        return tradeResult;
    }

    /**
     * @notice Executes liquidation call for the position
     * @param vaultId The id of the vault
     * @param settlementData The route of settlement created by liquidator
     */
    function execLiquidationCall(uint256 vaultId, bytes memory settlementData) external {
        _predyPool.execLiquidationCall(vaultId, 1e18, ISettlement.SettlementData(address(this), settlementData));
    }

    function _verifyOrder(ResolvedOrder memory order) internal {
        order.validate();

        _permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(address(this)),
            order.info.trader,
            order.hash,
            GammaOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }
}
