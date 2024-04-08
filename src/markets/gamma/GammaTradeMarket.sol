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
import {PredyPoolQuoter} from "../../lens/PredyPoolQuoter.sol";

/**
 * @notice Gamma trade market contract
 */
contract GammaTradeMarket is IFillerMarket, BaseMarketUpgradable, ReentrancyGuardUpgradeable {
    using ResolvedOrderLib for ResolvedOrder;

    using GammaOrderLib for GammaOrder;

    using Permit2Lib for ResolvedOrder;
    using SafeTransferLib for ERC20;

    error PositionNotFound();
    error PositionIsNotClosed();
    error SignerISNotPositionOwner();
    error TooShortHedgeInterval();
    error HedgeTriggerNotMatched();
    error AutoCloseTriggerNotMatched();
    error ValueIsLessThanLimit(int256 value);

    struct UserPosition {
        uint256 vaultId;
        address owner;
        uint64 pairId;
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

    mapping(address owner => uint256[]) public positionIDs;
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

                // remove position index
                _removePosition(callbackData.trader, tradeParams.vaultId);
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

        _verifyOrder(resolvedOrder);

        // execute trade
        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                gammaOrder.pairId,
                gammaOrder.positionId,
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

        UserPosition storage userPosition = userPositions[tradeResult.vaultId];

        _saveUserPosition(userPosition, gammaOrder.modifyInfo);

        if (userPosition.vaultId == 0) {
            userPosition.vaultId = tradeResult.vaultId;
            userPosition.owner = gammaOrder.info.trader;
            userPosition.pairId = gammaOrder.pairId;

            _addPositionIndex(gammaOrder.info.trader, userPosition.vaultId);

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
    function modifyAutoHedgeAndClose(GammaOrder memory gammaOrder, bytes memory sig) external nonReentrant {
        require(
            gammaOrder.quantity == 0 && gammaOrder.quantitySqrt == 0 && gammaOrder.marginAmount == 0, "Invalid Order"
        );

        ResolvedOrder memory resolvedOrder = GammaOrderLib.resolve(gammaOrder, sig);

        _verifyOrder(resolvedOrder);

        // save user position
        UserPosition storage userPosition = _getPosition(gammaOrder.info.trader, gammaOrder.positionId);

        _saveUserPosition(userPosition, gammaOrder.modifyInfo);
    }

    function autoHedge(address trader, uint256 positionId, SettlementParamsV3 memory settlementParams)
        external
        nonReentrant
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        UserPosition memory userPosition = _getPosition(trader, positionId);

        uint256 sqrtPrice = _predyPool.getSqrtIndexPrice(userPosition.pairId);

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
            userPosition.pairId,
            userPosition.vaultId,
            -delta,
            0,
            abi.encode(CallbackData(CallbackSource.TRADE, trader, 0))
        );

        tradeResult = _predyPool.trade(tradeParams, _getSettlementDataFromV3(settlementParams, msg.sender));

        SlippageLib.checkPrice(sqrtPrice, tradeResult, slippageTorelance, 0);
    }

    function autoClose(address trader, uint256 positionId, SettlementParamsV3 memory settlementParams)
        external
        nonReentrant
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        // save user position
        UserPosition memory userPosition = _getPosition(trader, positionId);

        // check auto close condition
        uint256 sqrtPrice = _predyPool.getSqrtIndexPrice(userPosition.pairId);

        (bool closeRequired, uint256 slippageTorelance) = _validateCloseCondition(userPosition, sqrtPrice);

        if (!closeRequired) {
            revert AutoCloseTriggerNotMatched();
        }

        // execute close
        DataType.Vault memory vault = _predyPool.getVault(userPosition.vaultId);

        IPredyPool.TradeParams memory tradeParams = IPredyPool.TradeParams(
            userPosition.pairId,
            userPosition.vaultId,
            -vault.openPosition.perp.amount,
            -vault.openPosition.sqrtPerp.amount,
            abi.encode(CallbackData(CallbackSource.TRADE, trader, 0))
        );

        tradeResult = _predyPool.trade(tradeParams, _getSettlementDataFromV3(settlementParams, msg.sender));

        SlippageLib.checkPrice(sqrtPrice, tradeResult, slippageTorelance, 0);
    }

    function quoteTrade(GammaOrder memory gammaOrder, SettlementParams memory settlementParams) external {
        // execute trade
        _predyPool.trade(
            IPredyPool.TradeParams(
                gammaOrder.pairId,
                gammaOrder.positionId,
                gammaOrder.quantity,
                gammaOrder.quantitySqrt,
                abi.encode(CallbackData(CallbackSource.QUOTE, gammaOrder.info.trader, gammaOrder.marginAmount))
            ),
            _getSettlementData(settlementParams)
        );
    }

    function checkAutoHedge(address trader, uint256 positionId) external view returns (bool) {
        UserPosition memory userPosition = _getPosition(trader, positionId);

        uint256 sqrtPrice = _predyPool.getSqrtIndexPrice(userPosition.pairId);

        (bool hedgeRequired,) = _validateHedgeCondition(userPosition, sqrtPrice);

        return hedgeRequired;
    }

    function checkAutoClose(address trader, uint256 positionId) external view returns (bool) {
        UserPosition memory userPosition = _getPosition(trader, positionId);

        uint256 sqrtPrice = _predyPool.getSqrtIndexPrice(userPosition.pairId);

        (bool closeRequired,) = _validateCloseCondition(userPosition, sqrtPrice);

        return closeRequired;
    }

    struct UserPositionResult {
        UserPosition userPosition;
        IPredyPool.VaultStatus vaultStatus;
        DataType.Vault vault;
    }

    function getUserPositions(address owner) external returns (UserPositionResult[] memory) {
        uint256[] memory userPositionIDs = positionIDs[owner];

        UserPositionResult[] memory results = new UserPositionResult[](userPositionIDs.length);

        for (uint64 i = 0; i < userPositionIDs.length; i++) {
            uint256 positionId = userPositionIDs[i];

            results[i] = _getUserPosition(positionId);
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
            userPosition, _quoter.quoteVaultStatus(userPosition.vaultId), _predyPool.getVault(userPosition.vaultId)
        );
    }

    function _addPositionIndex(address trader, uint256 newPositionId) internal {
        positionIDs[trader].push(newPositionId);
    }

    function removePosition(address trader, uint256 positionId) external {
        DataType.Vault memory vault = _predyPool.getVault(userPositions[positionId].vaultId);

        if (vault.margin != 0 || vault.openPosition.perp.amount != 0 || vault.openPosition.sqrtPerp.amount != 0) {
            revert PositionIsNotClosed();
        }

        _removePosition(trader, positionId);
    }

    function _removePosition(address trader, uint256 positionId) internal {
        require(userPositions[positionId].owner == trader, "trader is not owner");

        uint256 index = _getPositionIndex(positionIDs[trader], positionId);

        _removePositionIndex(positionIDs[trader], index);
    }

    function _removePositionIndex(uint256[] storage traderPositionIDs, uint256 index) internal {
        traderPositionIDs[index] = traderPositionIDs[traderPositionIDs.length - 1];
        traderPositionIDs.pop();
    }

    function _getPositionIndex(uint256[] memory traderPositionIDs, uint256 positionId)
        internal
        pure
        returns (uint256)
    {
        uint256 index = type(uint256).max;

        for (uint256 i = 0; i < traderPositionIDs.length; i++) {
            if (traderPositionIDs[i] == positionId) {
                index = i;
                break;
            }
        }

        return index;
    }

    function _getPosition(address trader, uint256 positionId)
        internal
        view
        returns (UserPosition storage userPosition)
    {
        userPosition = userPositions[positionId];

        if (positionId == 0 || userPosition.vaultId == 0) {
            revert PositionNotFound();
        }

        if (userPosition.owner != trader) {
            revert SignerISNotPositionOwner();
        }

        return userPosition;
    }

    function _saveUserPosition(UserPosition storage userPosition, GammaModifyInfo memory modifyInfo) internal {
        if (!modifyInfo.isEnabled) {
            return;
        }

        if (1 hours > modifyInfo.hedgeInterval) {
            revert TooShortHedgeInterval();
        }

        require(modifyInfo.maxSlippageTolerance >= modifyInfo.minSlippageTolerance);
        require(modifyInfo.maxSlippageTolerance <= 2 * Bps.ONE);

        // auto close condition
        userPosition.expiration = modifyInfo.expiration;
        userPosition.lowerLimit = modifyInfo.lowerLimit;
        userPosition.upperLimit = modifyInfo.upperLimit;

        // auto hedge condition
        userPosition.hedgeInterval = modifyInfo.hedgeInterval;
        userPosition.sqrtPriceTrigger = modifyInfo.sqrtPriceTrigger;
        userPosition.minSlippageTolerance = modifyInfo.minSlippageTolerance;
        userPosition.maxSlippageTolerance = modifyInfo.maxSlippageTolerance;
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
