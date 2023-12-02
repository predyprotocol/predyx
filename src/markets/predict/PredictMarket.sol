// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IPredyPool.sol";
import "../../interfaces/ILendingPool.sol";
import "../../interfaces/IFillerMarket.sol";
import "../../interfaces/IOrderValidator.sol";
import "../../base/BaseMarket.sol";
import "../../libraries/logic/LiquidationLogic.sol";
import "../../libraries/orders/Permit2Lib.sol";
import "../../libraries/orders/ResolvedOrder.sol";
import "../../libraries/math/Bps.sol";
import {PredictOrderLib, PredictOrder} from "./PredictOrder.sol";
import "../../libraries/math/Math.sol";
import {PredyPoolQuoter} from "../../lens/PredyPoolQuoter.sol";

/**
 * @notice Predict market contract
 * A trader can open position with any duration.
 * Anyone can close the position after expiration timestamp.
 */
contract PredictMarket is IFillerMarket, BaseMarket {
    using ResolvedOrderLib for ResolvedOrder;
    using PredictOrderLib for PredictOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;
    using Bps for uint256;

    error NullOwner();
    error DurationTooLong();
    error CloseBeforeExpiration();

    IPermit2 private immutable _permit2;

    // The duration of dutch auction is 20 minutes
    uint256 private constant _AUCTION_DURATION = 20 minutes;

    // The auction starts with min slippage(0.1%) and ends with max slippage(2%)
    uint256 private constant _MIN_SLIPPAGE = 1001000;
    uint256 private constant _MAX_SLIPPAGE = 1020000;

    struct UserPosition {
        address owner;
        uint256 expiration;
    }

    enum CallbackSource {
        OPEN,
        CLOSE
    }

    struct CallbackData {
        CallbackSource callbackSource;
        uint256 depositAmount;
    }

    mapping(uint256 vaultId => UserPosition) public userPositions;

    event Opened(address trader, uint256 vaultId, uint256 expiration, uint256 duration);
    event Closed(uint256 vaultId, uint256 closeValue);

    constructor(IPredyPool predyPool, address permit2Address, address whitelistFiller)
        BaseMarket(predyPool, whitelistFiller)
    {
        _permit2 = IPermit2(permit2Address);
    }

    function predyTradeAfterCallback(IPredyPool.TradeParams memory tradeParams, IPredyPool.TradeResult memory)
        external
        override(BaseHookCallback)
        onlyPredyPool
    {
        CallbackData memory callbackData = abi.decode(tradeParams.extraData, (CallbackData));

        if (callbackData.callbackSource == CallbackSource.OPEN) {
            TransferHelper.safeTransfer(
                _getQuoteTokenAddress(tradeParams.pairId), address(_predyPool), callbackData.depositAmount
            );
        } else if (callbackData.callbackSource == CallbackSource.CLOSE) {
            DataType.Vault memory vault = _predyPool.getVault(tradeParams.vaultId);

            uint256 closeValue = uint256(vault.margin);

            ILendingPool(address(_predyPool)).take(true, address(this), closeValue);

            TransferHelper.safeTransfer(
                _getQuoteTokenAddress(tradeParams.pairId), userPositions[tradeParams.vaultId].owner, closeValue
            );

            emit Closed(tradeParams.vaultId, closeValue);
        }
    }

    /**
     * @notice Verifies signature of the order and open new predict position
     * @param order The order signed by trader
     * @param settlementData The route of settlement created by filler
     * @return tradeResult The result of trade
     */
    function executeOrder(SignedOrder memory order, ISettlement.SettlementData memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        PredictOrder memory predictOrder = abi.decode(order.order, (PredictOrder));
        ResolvedOrder memory resolvedOrder = PredictOrderLib.resolve(predictOrder, order.sig);

        validateQuoteTokenAddress(predictOrder.pairId, predictOrder.entryTokenAddress);

        // only whitelisted filler can open position
        if (msg.sender != _whitelistFiller) {
            revert CallerIsNotFiller();
        }

        _verifyOrder(resolvedOrder);

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                predictOrder.pairId,
                0,
                predictOrder.tradeAmount,
                predictOrder.tradeAmountSqrt,
                abi.encode(CallbackData(CallbackSource.OPEN, predictOrder.marginAmount))
            ),
            settlementData
        );

        saveUserPosition(tradeResult.vaultId, predictOrder.info.trader, block.timestamp + predictOrder.duration);

        _predyPool.updateRecepient(tradeResult.vaultId, predictOrder.info.trader);

        IPredictOrderValidator(predictOrder.validatorAddress).validate(predictOrder, tradeResult);

        emit Opened(
            predictOrder.info.trader,
            tradeResult.vaultId,
            predictOrder.duration,
            userPositions[tradeResult.vaultId].expiration
        );

        return tradeResult;
    }

    /**
     * @notice Closes a predict position
     * @param positionId The id of position
     * @param settlementData The route of settlement created by filler
     * @return tradeResult The result of trade
     * @dev Anyone can call this function
     */
    function close(uint256 positionId, ISettlement.SettlementData memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        UserPosition storage userPosition = userPositions[positionId];

        require(0 < userPosition.expiration);

        if (userPosition.expiration > block.timestamp) {
            revert CloseBeforeExpiration();
        }

        uint256 expiration = userPosition.expiration;

        userPosition.expiration = 0;

        DataType.Vault memory vault = _predyPool.getVault(positionId);

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                vault.openPosition.pairId,
                positionId,
                -vault.openPosition.perp.amount,
                -vault.openPosition.sqrtPerp.amount,
                abi.encode(CallbackData(CallbackSource.CLOSE, 0))
            ),
            settlementData
        );

        LiquidationLogic.checkPrice(
            _predyPool.getSqrtIndexPrice(vault.openPosition.pairId),
            tradeResult,
            _calculateSlippageTolerance(expiration, block.timestamp),
            vault.openPosition.sqrtPerp.amount != 0
        );
    }

    function saveUserPosition(uint256 vaultId, address owner, uint256 expiration) internal {
        require(owner != address(0) && vaultId > 0);

        if (expiration > block.timestamp + 30 days) {
            revert DurationTooLong();
        }

        userPositions[vaultId].owner = owner;
        userPositions[vaultId].expiration = expiration;
    }

    function _calculateSlippageTolerance(uint256 startTime, uint256 currentTime) internal pure returns (uint256) {
        if (currentTime <= startTime) {
            return _MIN_SLIPPAGE;
        }

        uint256 elapsed = (currentTime - startTime) * 1e4 / _AUCTION_DURATION;

        if (elapsed > 1e4) {
            return _MAX_SLIPPAGE;
        }

        return (_MIN_SLIPPAGE + elapsed * (_MAX_SLIPPAGE - _MIN_SLIPPAGE) / 1e4);
    }

    function _verifyOrder(ResolvedOrder memory order) internal {
        order.validate();

        _permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(address(this)),
            order.info.trader,
            order.hash,
            PredictOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }
}
