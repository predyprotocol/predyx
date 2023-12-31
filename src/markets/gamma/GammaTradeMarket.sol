// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "../../interfaces/IPredyPool.sol";
import "../../interfaces/IFillerMarket.sol";
import "../../interfaces/IOrderValidator.sol";
import "../../base/BaseMarket.sol";
import "../../libraries/orders/Permit2Lib.sol";
import "../../libraries/orders/ResolvedOrder.sol";
import "../../libraries/logic/LiquidationLogic.sol";
import {SlippageLib} from "../../libraries/SlippageLib.sol";
import {Bps} from "../../libraries/math/Bps.sol";
import "./GammaOrder.sol";
import {PredyPoolQuoter} from "../../lens/PredyPoolQuoter.sol";

/**
 * @notice Gamma trade market contract
 */
contract GammaTradeMarket is IFillerMarket, BaseMarket, ReentrancyGuard {
    using ResolvedOrderLib for ResolvedOrder;
    using GammaOrderLib for GammaOrder;
    using Permit2Lib for ResolvedOrder;
    using SafeTransferLib for ERC20;

    error TooSmallHedgeInterval();
    error HedgeTriggerNotMatched();

    struct UserPosition {
        uint256 vaultId;
        uint256 lastHedgedTime;
        uint256 hedgeInterval;
        uint256 lastHedgedSqrtPrice;
        uint256 sqrtPriceTrigger;
        uint64 minSlippageTolerance;
        uint64 maxSlippageTolerance;
    }

    enum CallbackSource {
        TRADE,
        QUOTE
    }

    struct CallbackData {
        CallbackSource callbackSource;
        address trader;
        int256 marginAmountUpdate;
        address validatorAddress;
        bytes validationData;
    }

    // The duration of dutch auction is 16 minutes
    uint256 private constant _AUCTION_DURATION = 16 minutes;
    // The range of auction price
    uint256 private constant _AUCTION_RANGE = 100;

    IPermit2 private immutable _permit2;

    mapping(address owner => mapping(uint256 pairId => UserPosition)) public userPositions;

    event GammaPositionTraded(
        address indexed trader,
        uint256 pairId,
        uint256 vaultId,
        uint256 hedgeInterval,
        uint256 sqrtPriceTrigger,
        IPredyPool.Payoff payoff,
        int256 fee,
        int256 marginAmount
    );
    event GammaPositionHedged(
        address indexed trader,
        uint256 pairId,
        uint256 vaultId,
        uint256 sqrtPrice,
        int256 delta,
        IPredyPool.Payoff payoff,
        int256 fee
    );

    constructor(IPredyPool predyPool, address permit2Address, address whitelistFiller, address quoterAddress)
        BaseMarket(predyPool, whitelistFiller, quoterAddress)
    {
        _permit2 = IPermit2(permit2Address);
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallback) onlyPredyPool {
        CallbackData memory callbackData = abi.decode(tradeParams.extraData, (CallbackData));
        ERC20 quoteToken = ERC20(_getQuoteTokenAddress(tradeParams.pairId));

        if (callbackData.callbackSource == CallbackSource.QUOTE) {
            IOrderValidator(callbackData.validatorAddress).validate(
                tradeParams.tradeAmount, tradeParams.tradeAmountSqrt, callbackData.validationData, tradeResult
            );

            _revertTradeResult(tradeResult);
        } else if (callbackData.callbackSource == CallbackSource.TRADE) {
            if (tradeResult.minMargin == 0) {
                DataType.Vault memory vault = _predyPool.getVault(tradeParams.vaultId);

                _predyPool.take(true, callbackData.trader, uint256(vault.margin));
            } else {
                int256 marginAmountUpdate = callbackData.marginAmountUpdate;

                if (marginAmountUpdate > 0) {
                    quoteToken.safeTransfer(address(_predyPool), uint256(marginAmountUpdate));
                } else if (marginAmountUpdate < 0) {
                    _predyPool.take(true, callbackData.trader, uint256(-marginAmountUpdate));
                }
            }
        }
    }

    /**
     * @notice Verifies signature of the order and executes trade
     * @param order The order signed by trader
     * @param settlementParams The route of settlement created by filler
     */
    function executeOrder(SignedOrder memory order, SettlementParams memory settlementParams)
        external
        nonReentrant
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        GammaOrder memory gammaOrder = abi.decode(order.order, (GammaOrder));
        ResolvedOrder memory resolvedOrder = GammaOrderLib.resolve(gammaOrder, order.sig);

        _validateQuoteTokenAddress(gammaOrder.pairId, gammaOrder.entryTokenAddress);

        _verifyOrder(resolvedOrder);

        UserPosition storage userPosition = userPositions[gammaOrder.info.trader][gammaOrder.pairId];

        _saveUserPosition(
            userPosition,
            gammaOrder.hedgeInterval,
            gammaOrder.sqrtPriceTrigger,
            gammaOrder.minSlippageTolerance,
            gammaOrder.maxSlippageTolerance
        );

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                gammaOrder.pairId,
                userPosition.vaultId,
                gammaOrder.tradeAmount,
                gammaOrder.tradeAmountSqrt,
                abi.encode(
                    CallbackData(
                        CallbackSource.TRADE, gammaOrder.info.trader, gammaOrder.marginAmount, address(0), bytes("")
                    )
                )
            ),
            _getSettlementData(settlementParams)
        );

        if (tradeResult.minMargin > 0) {
            // only whitelisted filler can open position
            if (msg.sender != whitelistFiller) {
                revert CallerIsNotFiller();
            }
        }

        if (userPosition.vaultId == 0) {
            userPosition.vaultId = tradeResult.vaultId;

            _predyPool.updateRecepient(tradeResult.vaultId, gammaOrder.info.trader);
        }

        IOrderValidator(gammaOrder.validatorAddress).validate(
            gammaOrder.tradeAmount, gammaOrder.tradeAmountSqrt, gammaOrder.validationData, tradeResult
        );

        emit GammaPositionTraded(
            gammaOrder.info.trader,
            gammaOrder.pairId,
            tradeResult.vaultId,
            gammaOrder.hedgeInterval,
            gammaOrder.sqrtPriceTrigger,
            tradeResult.payoff,
            tradeResult.fee,
            gammaOrder.marginAmount
        );

        return tradeResult;
    }

    /**
     * @notice Executes delta hedging
     * @param owner owner address
     * @param pairId The id of pair
     * @param settlementParams The route of settlement created by filler
     * @return tradeResult The result of trade
     * @dev Anyone can call this function
     */
    function execDeltaHedge(address owner, uint256 pairId, SettlementParams memory settlementParams)
        external
        nonReentrant
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        UserPosition storage userPosition = userPositions[owner][pairId];

        require(userPosition.vaultId > 0);

        DataType.Vault memory vault = _predyPool.getVault(userPosition.vaultId);

        uint256 sqrtPrice = _predyPool.getSqrtIndexPrice(vault.openPosition.pairId);

        int256 delta = _calculateDelta(sqrtPrice, vault.openPosition.sqrtPerp.amount, vault.openPosition.perp.amount);

        (bool hedgeRequired, uint256 slippageTorelance) = _validateHedgeCondition(userPosition, sqrtPrice);

        if (!hedgeRequired) {
            revert HedgeTriggerNotMatched();
        }

        userPosition.lastHedgedSqrtPrice = sqrtPrice;
        userPosition.lastHedgedTime = block.timestamp;

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                vault.openPosition.pairId,
                userPosition.vaultId,
                -delta,
                0,
                abi.encode(CallbackData(CallbackSource.TRADE, owner, 0, address(0), bytes("")))
            ),
            _getSettlementData(settlementParams)
        );

        SlippageLib.checkPrice(sqrtPrice, tradeResult, slippageTorelance, 0);

        emit GammaPositionHedged(
            owner, pairId, userPosition.vaultId, sqrtPrice, delta, tradeResult.payoff, tradeResult.fee
        );
    }

    /// @notice Estimate transaction results and return with revert message
    function quoteExecuteOrder(GammaOrder memory gammaOrder, SettlementParams memory settlementParams) external {
        _predyPool.trade(
            IPredyPool.TradeParams(
                gammaOrder.pairId,
                userPositions[gammaOrder.info.trader][gammaOrder.pairId].vaultId,
                gammaOrder.tradeAmount,
                gammaOrder.tradeAmountSqrt,
                abi.encode(
                    CallbackData(
                        CallbackSource.QUOTE,
                        gammaOrder.info.trader,
                        0,
                        gammaOrder.validatorAddress,
                        gammaOrder.validationData
                    )
                )
            ),
            _getSettlementData(settlementParams)
        );
    }

    function getUserPosition(address owner, uint256 pairId)
        external
        returns (UserPosition memory userPosition, IPredyPool.VaultStatus memory, DataType.Vault memory)
    {
        userPosition = userPositions[owner][pairId];

        return (userPosition, _quoter.quoteVaultStatus(userPosition.vaultId), _predyPool.getVault(userPosition.vaultId));
    }

    function _saveUserPosition(
        UserPosition storage userPosition,
        uint256 hedgeInterval,
        uint256 sqrtPriceTrigger,
        uint64 minSlippageTolerance,
        uint64 maxSlippageTolerance
    ) internal {
        if (2 hours > hedgeInterval) {
            revert TooSmallHedgeInterval();
        }

        require(maxSlippageTolerance >= minSlippageTolerance);
        require(maxSlippageTolerance <= Bps.ONE);

        userPosition.hedgeInterval = hedgeInterval;
        userPosition.sqrtPriceTrigger = sqrtPriceTrigger;
        userPosition.minSlippageTolerance = minSlippageTolerance + Bps.ONE;
        userPosition.maxSlippageTolerance = maxSlippageTolerance + Bps.ONE;
    }

    function _calculateDelta(uint256 _sqrtPrice, int256 _sqrtAmount, int256 perpAmount)
        internal
        pure
        returns (int256)
    {
        return perpAmount + _sqrtAmount * int256(Constants.Q96) / int256(_sqrtPrice);
    }

    function _validateHedgeCondition(UserPosition memory userPosition, uint256 sqrtIndexPrice)
        internal
        view
        returns (bool, uint256 slippageTolerance)
    {
        if (userPosition.lastHedgedTime + userPosition.hedgeInterval <= block.timestamp) {
            return (
                true,
                _calculateSlippageTolerance(
                    userPosition.lastHedgedTime + userPosition.hedgeInterval,
                    block.timestamp,
                    userPosition.minSlippageTolerance,
                    userPosition.maxSlippageTolerance
                    )
            );
        }

        // if sqrtPriceTrigger is 0, it means that the user doesn't want to use this feature
        if (userPosition.sqrtPriceTrigger == 0) {
            return (false, 0);
        }

        uint256 upperThreshold = userPosition.lastHedgedSqrtPrice * userPosition.sqrtPriceTrigger / 1e4;
        uint256 lowerThreshold = userPosition.lastHedgedSqrtPrice * 1e4 / userPosition.sqrtPriceTrigger;

        if (lowerThreshold >= sqrtIndexPrice) {
            return (
                true,
                _calculateSlippageToleranceByPrice(
                    sqrtIndexPrice, lowerThreshold, userPosition.minSlippageTolerance, userPosition.maxSlippageTolerance
                    )
            );
        }

        if (upperThreshold <= sqrtIndexPrice) {
            return (
                true,
                _calculateSlippageToleranceByPrice(
                    upperThreshold, sqrtIndexPrice, userPosition.minSlippageTolerance, userPosition.maxSlippageTolerance
                    )
            );
        }

        return (false, 0);
    }

    function _calculateSlippageTolerance(
        uint256 startTime,
        uint256 currentTime,
        uint256 minSlippageTolerance,
        uint256 maxSlippageTolerance
    ) internal pure returns (uint256) {
        if (currentTime <= startTime) {
            return minSlippageTolerance;
        }

        uint256 elapsed = (currentTime - startTime) * 1e4 / _AUCTION_DURATION;

        if (elapsed > 1e4) {
            return maxSlippageTolerance;
        }

        return (minSlippageTolerance + elapsed * (maxSlippageTolerance - minSlippageTolerance) / 1e4);
    }

    function _calculateSlippageToleranceByPrice(
        uint256 price1,
        uint256 price2,
        uint256 minSlippageTolerance,
        uint256 maxSlippageTolerance
    ) internal pure returns (uint256) {
        if (price2 <= price1) {
            return minSlippageTolerance;
        }

        uint256 ratio = (price2 * 1e4 / price1 - 1e4);

        if (ratio > _AUCTION_RANGE) {
            return maxSlippageTolerance;
        }

        return (minSlippageTolerance + ratio * (maxSlippageTolerance - minSlippageTolerance) / _AUCTION_RANGE);
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
