// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import "../../interfaces/IFillerMarket.sol";
import "../../interfaces/IOrderValidator.sol";
import {BaseMarketUpgradable} from "../../base/BaseMarketUpgradable.sol";
import {BaseHookCallbackUpgradable} from "../../base/BaseHookCallbackUpgradable.sol";
import "../../libraries/orders/Permit2Lib.sol";
import "../../libraries/orders/ResolvedOrder.sol";
import "../../libraries/logic/LiquidationLogic.sol";
import {SlippageLib} from "../../libraries/SlippageLib.sol";
import {Bps} from "../../libraries/math/Bps.sol";
import "./GammaOrder.sol";
import "./GammaModifyOrder.sol";
import {PredyPoolQuoter} from "../../lens/PredyPoolQuoter.sol";

/**
 * @notice Gamma trade market contract
 */
contract GammaTradeMarket is IFillerMarket, BaseMarketUpgradable, ReentrancyGuardUpgradeable {
    using ResolvedOrderLib for ResolvedOrder;

    using GammaOrderLib for GammaOrder;
    using GammaModifyOrderLib for GammaModifyOrder;

    using Permit2Lib for ResolvedOrder;
    using SafeTransferLib for ERC20;

    error PositionNotFound();
    error TooShortHedgeInterval();
    error HedgeTriggerNotMatched();
    error AutoCloseTriggerNotMatched();
    error ValueIsLessThanLimit(int256 value);

    struct UserPosition {
        uint256 vaultId;
        uint256 expiration;
        uint256 lowerLimit;
        uint256 upperLimit;
        uint256 lastHedgedTime;
        uint256 hedgeInterval;
        uint256 lastHedgedSqrtPrice;
        uint256 sqrtPriceTrigger;
        uint64 minSlippageTolerance;
        uint64 maxSlippageTolerance;
    }

    enum CallbackSource {
        TRADE,
        HEDGE,
        QUOTE
    }

    struct CallbackData {
        CallbackSource callbackSource;
        address trader;
        int256 marginAmountUpdate;
    }

    // The duration of dutch auction is 16 minutes
    uint256 private constant _AUCTION_DURATION = 16 minutes;
    // The range of auction price
    uint256 private constant _AUCTION_RANGE = 100;

    IPermit2 private _permit2;

    uint256 public positionCounter;

    mapping(address owner => mapping(uint256 pairId => uint256[32])) public positionIDs;
    mapping(uint256 positionId => UserPosition) public userPositions;

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

    constructor() {}

    function initialize(IPredyPool predyPool, address permit2Address, address whitelistFiller, address quoterAddress)
        public
        initializer
    {
        __ReentrancyGuard_init();
        __BaseMarket_init(predyPool, whitelistFiller, quoterAddress);

        _permit2 = IPermit2(permit2Address);

        positionCounter = 1;
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallbackUpgradable) onlyPredyPool {
        CallbackData memory callbackData = abi.decode(tradeParams.extraData, (CallbackData));
        ERC20 quoteToken = ERC20(_getQuoteTokenAddress(tradeParams.pairId));

        if (callbackData.callbackSource == CallbackSource.QUOTE) {
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

    // open position
    function executeTrade(GammaOrder memory gammaOrder, bytes memory sig, SettlementParamsV3 memory settlementParams)
        external
        nonReentrant
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        ResolvedOrder memory resolvedOrder = GammaOrderLib.resolve(gammaOrder, sig);

        _validateQuoteTokenAddress(gammaOrder.pairId, gammaOrder.entryTokenAddress);

        _verifyOrder(resolvedOrder, GammaOrderLib.PERMIT2_ORDER_TYPE);

        // create user position
        UserPosition storage userPosition =
            _createOrGetPosition(gammaOrder.info.trader, gammaOrder.pairId, gammaOrder.slotId);

        // execute trade
        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                gammaOrder.pairId,
                userPosition.vaultId,
                gammaOrder.quantity,
                gammaOrder.quantitySqrt,
                abi.encode(CallbackData(CallbackSource.TRADE, gammaOrder.info.trader, gammaOrder.marginAmount))
            ),
            _getSettlementDataFromV3(settlementParams, msg.sender)
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

        // TODO: check value >= gammaOrder.limitValue
        _checkTradeValue(tradeResult, gammaOrder.limitValue);
    }

    function _checkTradeValue(IPredyPool.TradeResult memory tradeResult, int256 limitValue) internal pure {
        int256 tradeValue = tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff
            + tradeResult.payoff.sqrtEntryUpdate + tradeResult.payoff.sqrtPayoff;

        if (tradeValue < limitValue) {
            revert ValueIsLessThanLimit(tradeValue);
        }
    }

    // modify position (hedge or close)
    function modifyAutoHedgeAndClose(GammaModifyOrder memory gammaOrder, bytes memory sig) external nonReentrant {
        ResolvedOrder memory resolvedOrder = GammaModifyOrderLib.resolve(gammaOrder, sig);

        _verifyOrder(resolvedOrder, GammaModifyOrderLib.PERMIT2_ORDER_TYPE);

        // save user position
        UserPosition storage userPosition =
            _createOrGetPosition(gammaOrder.info.trader, gammaOrder.pairId, gammaOrder.slotId);

        _saveUserPosition(userPosition, gammaOrder);
    }

    function autoHedge(address trader, uint256 pairId, uint64 slotId, SettlementParamsV3 memory settlementParams)
        external
        nonReentrant
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        UserPosition memory userPosition = _getPosition(trader, pairId, slotId);

        uint256 sqrtPrice = _predyPool.getSqrtIndexPrice(pairId);

        // check auto hedge condition
        (bool hedgeRequired, uint256 slippageTorelance) = _validateHedgeCondition(userPosition, sqrtPrice);

        if (!hedgeRequired) {
            revert HedgeTriggerNotMatched();
        }

        userPosition.lastHedgedSqrtPrice = sqrtPrice;
        userPosition.lastHedgedTime = block.timestamp;

        // execute trade
        DataType.Vault memory vault = _predyPool.getVault(userPosition.vaultId);

        int256 delta = _calculateDelta(sqrtPrice, vault.openPosition.sqrtPerp.amount, vault.openPosition.perp.amount);

        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            pairId, userPosition.vaultId, -delta, 0, abi.encode(CallbackData(CallbackSource.TRADE, trader, 0))
        );

        tradeResult = _predyPool.trade(tradeParams, _getSettlementDataFromV3(settlementParams, msg.sender));

        SlippageLib.checkPrice(sqrtPrice, tradeResult, slippageTorelance, 0);
    }

    function autoClose(address trader, uint256 pairId, uint64 slotId, SettlementParamsV3 memory settlementParams)
        external
        nonReentrant
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        // save user position
        UserPosition memory userPosition = _getPosition(trader, pairId, slotId);

        // check auto close condition
        uint256 sqrtPrice = _predyPool.getSqrtIndexPrice(pairId);

        (bool closeRequired, uint256 slippageTorelance) = _validateCloseCondition(userPosition, sqrtPrice);

        if (!closeRequired) {
            revert AutoCloseTriggerNotMatched();
        }

        // execute close
        DataType.Vault memory vault = _predyPool.getVault(userPosition.vaultId);

        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            pairId,
            userPosition.vaultId,
            -vault.openPosition.perp.amount,
            -vault.openPosition.sqrtPerp.amount,
            abi.encode(CallbackData(CallbackSource.TRADE, trader, 0))
        );

        tradeResult = _predyPool.trade(tradeParams, _getSettlementDataFromV3(settlementParams, msg.sender));

        SlippageLib.checkPrice(sqrtPrice, tradeResult, slippageTorelance, 0);
    }

    function quoteTrade(GammaOrder memory gammaOrder, SettlementParams memory settlementParams) external {
        // create user position
        UserPosition storage userPosition =
            _createOrGetPosition(gammaOrder.info.trader, gammaOrder.pairId, gammaOrder.slotId);

        // execute trade
        _predyPool.trade(
            IPredyPool.TradeParams(
                gammaOrder.pairId,
                userPosition.vaultId,
                gammaOrder.quantity,
                gammaOrder.quantitySqrt,
                abi.encode(CallbackData(CallbackSource.QUOTE, gammaOrder.info.trader, gammaOrder.marginAmount))
            ),
            _getSettlementData(settlementParams)
        );
    }

    function checkAutoHedge(address trader, uint256 pairId, uint64 slotId) external view returns (bool) {
        UserPosition memory userPosition = _getPosition(trader, pairId, slotId);

        uint256 sqrtPrice = _predyPool.getSqrtIndexPrice(pairId);

        (bool hedgeRequired,) = _validateHedgeCondition(userPosition, sqrtPrice);

        return hedgeRequired;
    }

    function checkAutoClose(address trader, uint256 pairId, uint64 slotId) external view returns (bool) {
        UserPosition memory userPosition = _getPosition(trader, pairId, slotId);

        uint256 sqrtPrice = _predyPool.getSqrtIndexPrice(pairId);

        (bool closeRequired,) = _validateCloseCondition(userPosition, sqrtPrice);

        return closeRequired;
    }

    struct UserPositionResult {
        uint64 slotId;
        UserPosition userPosition;
        IPredyPool.VaultStatus vaultStatus;
        DataType.Vault vault;
    }

    function getUserPositions(address owner, uint256 pairId) external returns (UserPositionResult[] memory) {
        uint256 counts = 0;

        for (uint256 i = 0; i < 32; i++) {
            if (positionIDs[owner][pairId][i] > 0) {
                counts++;
            }
        }

        UserPositionResult[] memory results = new UserPositionResult[](counts);

        uint256 j = 0;

        for (uint64 i = 0; i < 32; i++) {
            uint256 positionId = positionIDs[owner][pairId][i];

            if (positionId > 0) {
                results[j] = _getUserPosition(positionId);
                results[j].slotId = i;
                j++;
            }
        }

        return results;
    }

    function _getUserPosition(uint256 positionId) internal returns (UserPositionResult memory result) {
        UserPosition memory userPosition = userPositions[positionId];

        if (userPosition.vaultId == 0) {
            // if user has no position, return empty vault status and vault
            return result;
        }

        return UserPositionResult(
            0, userPosition, _quoter.quoteVaultStatus(userPosition.vaultId), _predyPool.getVault(userPosition.vaultId)
        );
    }

    function _createOrGetPosition(address trader, uint256 pairId, uint64 slotId)
        internal
        returns (UserPosition storage userPosition)
    {
        uint256 positionId = positionIDs[trader][pairId][slotId];

        if (positionId == 0) {
            uint256 newPositionId = positionCounter;

            userPosition = userPositions[newPositionId];

            positionIDs[trader][pairId][slotId] = newPositionId;
            positionCounter++;
        } else {
            userPosition = userPositions[positionId];
        }
    }

    function _getPosition(address trader, uint256 pairId, uint64 slotId)
        internal
        view
        returns (UserPosition memory userPosition)
    {
        uint256 positionId = positionIDs[trader][pairId][slotId];

        if (positionId == 0) {
            revert PositionNotFound();
        } else {
            return userPositions[positionId];
        }
    }

    function _saveUserPosition(UserPosition storage userPosition, GammaModifyOrder memory gammaOrder) internal {
        if (1 hours > gammaOrder.hedgeInterval) {
            revert TooShortHedgeInterval();
        }

        require(gammaOrder.maxSlippageTolerance >= gammaOrder.minSlippageTolerance);
        require(gammaOrder.maxSlippageTolerance <= 2 * Bps.ONE);

        // auto close condition
        userPosition.expiration = gammaOrder.expiration;
        userPosition.lowerLimit = gammaOrder.lowerLimit;
        userPosition.upperLimit = gammaOrder.upperLimit;

        // auto hedge condition
        userPosition.hedgeInterval = gammaOrder.hedgeInterval;
        userPosition.sqrtPriceTrigger = gammaOrder.sqrtPriceTrigger;
        userPosition.minSlippageTolerance = gammaOrder.minSlippageTolerance;
        userPosition.maxSlippageTolerance = gammaOrder.maxSlippageTolerance;
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
        if (
            userPosition.hedgeInterval > 0
                && userPosition.lastHedgedTime + userPosition.hedgeInterval <= block.timestamp
        ) {
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

    function _validateCloseCondition(UserPosition memory userPosition, uint256 sqrtIndexPrice)
        internal
        view
        returns (bool, uint256 slippageTolerance)
    {
        if (userPosition.expiration <= block.timestamp) {
            return (
                true,
                _calculateSlippageTolerance(
                    userPosition.expiration,
                    block.timestamp,
                    userPosition.minSlippageTolerance,
                    userPosition.maxSlippageTolerance
                    )
            );
        }

        uint256 upperThreshold = userPosition.upperLimit;
        uint256 lowerThreshold = userPosition.lowerLimit;

        if (lowerThreshold > 0 && lowerThreshold >= sqrtIndexPrice) {
            return (
                true,
                _calculateSlippageToleranceByPrice(
                    sqrtIndexPrice, lowerThreshold, userPosition.minSlippageTolerance, userPosition.maxSlippageTolerance
                    )
            );
        }

        if (upperThreshold > 0 && upperThreshold <= sqrtIndexPrice) {
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

    function _verifyOrder(ResolvedOrder memory order, string memory permit2OrderType) internal {
        order.validate();

        _permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(address(this)),
            order.info.trader,
            order.hash,
            permit2OrderType,
            order.sig
        );
    }
}
