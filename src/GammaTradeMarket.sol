// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPredyPool.sol";
import "./interfaces/IFillerMarket.sol";
import "./interfaces/IOrderValidator.sol";
import "./base/BaseHookCallback.sol";
import "./libraries/market/Permit2Lib.sol";
import "./libraries/market/ResolvedOrder.sol";
import "./libraries/market/GeneralOrderLib.sol";
import "./libraries/math/Math.sol";

/**
 * @notice Gamma trade market contract
 */
contract GammaTradeMarket is IFillerMarket, BaseHookCallback {
    using ResolvedOrderLib for ResolvedOrder;
    using GeneralOrderLib for GeneralOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;

    IPermit2 _permit2;
    address _quoteTokenAddress;

    mapping(uint256 vaultId => address) public userPositions;

    constructor(IPredyPool _predyPool, address quoteTokenAddress, address permit2Address)
        BaseHookCallback(_predyPool)
    {
        _quoteTokenAddress = quoteTokenAddress;
        _permit2 = IPermit2(permit2Address);
    }

    function predyTradeAfterCallback(IPredyPool.TradeParams memory tradeParams, IPredyPool.TradeResult memory)
        external
        override(BaseHookCallback)
    {
        int256 marginAmountUpdate = abi.decode(tradeParams.extraData, (int256));

        if (marginAmountUpdate > 0) {
            IERC20(_quoteTokenAddress).transfer(address(_predyPool), uint256(marginAmountUpdate));
        } else if (marginAmountUpdate < 0) {
            _predyPool.take(true, address(this), uint256(-marginAmountUpdate));
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
            userPositions[tradeResult.vaultId] = generalOrder.info.trader;

            _predyPool.updateRecepient(tradeResult.vaultId, generalOrder.info.trader);
        } else {
            if (generalOrder.info.trader != userPositions[tradeResult.vaultId]) {
                revert IFillerMarket.SignerIsNotVaultOwner();
            }
        }

        // TODO: should have whote list for validatorAddress?
        IOrderValidator(generalOrder.validatorAddress).validate(generalOrder, tradeResult);

        if (generalOrder.marginAmount < 0) {
            IERC20(_quoteTokenAddress).transfer(generalOrder.info.trader, uint256(-generalOrder.marginAmount));
        }

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
            GeneralOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }
}
