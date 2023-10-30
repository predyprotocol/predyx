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
import "./libraries/orders/Permit2Lib.sol";
import "./libraries/orders/ResolvedOrder.sol";
import "./libraries/orders/GammaOrder.sol";
import "./libraries/math/Math.sol";
import "./libraries/Perp.sol";
import "./libraries/Constants.sol";
import "./libraries/DataType.sol";

/**
 * @title LeveragedGammaMarket
 * @notice Provides leveraged perps to retail traders
 */
contract LeveragedGammaMarket is IFillerMarket, BaseHookCallback {
    using ResolvedOrderLib for ResolvedOrder;
    using GammaOrderLib for GammaOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;
    using Math for int256;

    IPermit2 internal _permit2;

    // 12%: interest rates to be paid into the insurance fund
    uint256 public constant BORROW_FEE_RATE = 1200;
    // 0.1%: Min margin required for squart debt
    uint256 internal constant _MARGIN_RATIO_WITH_DEBT_SQUART = 1000;
    // The square root of 1%
    uint256 internal constant _RISK_RATIO = 100498756;

    struct InsurancePool {
        uint256 pairId;
        address fillerAddress;
        int256 marginAmount;
    }

    struct UserPosition {
        uint256 id;
        uint256 pairId;
        address filler;
        address owner;
        int256 positionAmount;
        int256 positionAmountSqrt;
        int256 assuranceMargin;
        int256 marginAmount;
        uint256 lastBorrowFeeCalculationTime;
    }

    enum CallbackSource {
        TRADE,
        LIQUIDATION
    }

    struct CallbackData {
        CallbackSource callbackSource;
        address caller;
        address trader;
        address filler;
        int256 marginAmountUpdate;
        bool createNew;
    }

    error CallerIsNotFiller();

    mapping(uint256 vaultId => UserPosition) public userPositions;

    mapping(address filler => mapping(uint256 pairId => InsurancePool)) public insurancePools;

    constructor(IPredyPool _predyPool, address permit2Address) BaseHookCallback(_predyPool) {
        _permit2 = IPermit2(permit2Address);
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallback) onlyPredyPool {
        CallbackData memory callbackData = abi.decode(tradeParams.extraData, (CallbackData));

        if (callbackData.createNew) {
            _createPosition(tradeParams.vaultId, tradeParams.pairId, callbackData.trader, callbackData.filler);
        }

        UserPosition storage userPosition = userPositions[tradeParams.vaultId];
        InsurancePool storage insurancePool = insurancePools[userPosition.filler][tradeParams.pairId];

        _handleTradeResult(userPosition, tradeResult, callbackData.caller == insurancePool.fillerAddress);

        _updateMargin(insurancePool, userPosition, callbackData, tradeResult.minMargin);
    }

    function _createPosition(uint256 vaultId, uint256 pairId, address owner, address filler) internal {
        userPositions[vaultId].id = vaultId;
        userPositions[vaultId].pairId = pairId;
        userPositions[vaultId].owner = owner;
        userPositions[vaultId].filler = filler;

        require(filler == insurancePools[filler][pairId].fillerAddress);

        // predy pool does not transfer margin if the position is liquidated
        _predyPool.updateRecepient(vaultId, address(0));
    }

    function _updateMargin(
        InsurancePool storage insurancePool,
        UserPosition storage userPosition,
        CallbackData memory callbackData,
        int256 positionMinMargin
    ) internal {
        // constraint: userPosition.marginAmount + userPosition.assuranceMargin = vault.margin
        int256 currentAssuranceMargin = userPosition.assuranceMargin;

        if (callbackData.callbackSource == CallbackSource.TRADE) {
            require(userPosition.marginAmount + callbackData.marginAmountUpdate >= 0);

            userPosition.assuranceMargin = positionMinMargin;
            insurancePool.marginAmount += currentAssuranceMargin - positionMinMargin;

            userPosition.marginAmount += callbackData.marginAmountUpdate;

            int256 diff = positionMinMargin - currentAssuranceMargin + callbackData.marginAmountUpdate;

            if (diff > 0) {
                IERC20(_quoteTokenMap[insurancePool.pairId]).transfer(address(_predyPool), uint256(diff));
            } else if (diff < 0) {
                _predyPool.take(true, address(this), uint256(-diff));
            }
        } else if (callbackData.callbackSource == CallbackSource.LIQUIDATION) {
            _predyPool.take(true, address(this), uint256(userPosition.marginAmount + userPosition.assuranceMargin));

            insurancePool.marginAmount += userPosition.assuranceMargin;

            userPosition.assuranceMargin = 0;
        }
    }

    /**
     * @notice Registers a new filler.
     */
    function addFillerPool(uint256 pairId) external returns (address) {
        return initFillerPool(pairId, msg.sender);
    }

    function depositToInsurancePool(uint256 pairId, uint256 depositAmount) external {
        require(insurancePools[msg.sender][pairId].fillerAddress == msg.sender);

        IERC20(_quoteTokenMap[pairId]).transferFrom(msg.sender, address(this), depositAmount);

        insurancePools[msg.sender][pairId].marginAmount += int256(depositAmount);
    }

    function withdrawFromInsurancePool(uint256 pairId, uint256 withdrawAmount) external {
        InsurancePool storage insurancePool = insurancePools[msg.sender][pairId];

        require(insurancePool.fillerAddress == msg.sender);

        insurancePool.marginAmount -= int256(withdrawAmount);

        require(insurancePool.marginAmount >= 0);

        IERC20(_quoteTokenMap[pairId]).transfer(msg.sender, withdrawAmount);
    }

    /**
     * @notice Verifies signature of the order and executes trade
     * @param order The order signed by trader
     * @param settlementData The route of settlement created by filler
     * @dev Fillers call this function
     */
    function executeOrder(address filler, SignedOrder memory order, ISettlement.SettlementData memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        GammaOrder memory gammaOrder = abi.decode(order.order, (GammaOrder));
        ResolvedOrder memory resolvedOrder = GammaOrderLib.resolve(gammaOrder, order.sig);

        require(_quoteTokenMap[gammaOrder.pairId] != address(0));
        require(gammaOrder.entryTokenAddress == _quoteTokenMap[gammaOrder.pairId]);

        _verifyOrder(resolvedOrder);

        if (gammaOrder.positionId > 0) {
            _updateBorrowFee(userPositions[gammaOrder.positionId]);
        }

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                gammaOrder.pairId,
                gammaOrder.positionId,
                gammaOrder.tradeAmount,
                gammaOrder.tradeAmountSqrt,
                abi.encode(
                    CallbackData(
                        CallbackSource.TRADE,
                        msg.sender,
                        gammaOrder.info.trader,
                        filler,
                        gammaOrder.marginAmount,
                        gammaOrder.positionId == 0
                    )
                )
            ),
            settlementData
        );

        gammaOrder.positionId = tradeResult.vaultId;

        if (gammaOrder.info.trader != userPositions[tradeResult.vaultId].owner) {
            revert IFillerMarket.SignerIsNotVaultOwner();
        }

        // TODO: only filler can open position
        // if (openAmount != 0 && userPositions[tradeResult.vaultId].filler != msg.sender) {
        //    revert CallerIsNotFiller();
        //}

        userPositions[tradeResult.vaultId].positionAmount += gammaOrder.tradeAmount;
        userPositions[tradeResult.vaultId].positionAmountSqrt += gammaOrder.tradeAmountSqrt;

        // TODO: should have white list for validatorAddress?
        IOrderValidator(gammaOrder.validatorAddress).validate(gammaOrder, tradeResult);

        _sendMarginToUser(gammaOrder.positionId, gammaOrder.marginAmount < 0 ? uint256(-gammaOrder.marginAmount) : 0);

        require(isPositionSafe(userPositions[tradeResult.vaultId]), "SAFE");

        return tradeResult;
    }

    // 0.5%
    uint256 constant _LIQ_SLIPPAGE = 50;
    // 3% scaled by 1e8
    uint256 constant _MAX_ACCEPTABLE_SQRT_PRICE_RANGE = 101488915;

    /**
     * @notice Executes liquidation call for the position
     * @param positionId The id of position
     * @param settlementData The route of settlement created by liquidator
     */
    function execLiquidationCall(uint64 positionId, ISettlement.SettlementData memory settlementData) external {
        UserPosition storage userPosition = userPositions[positionId];
        InsurancePool storage insurancePool = insurancePools[userPosition.filler][userPosition.pairId];

        // check vault is danger
        require(!isPositionSafe(userPosition), "NOT SAFE");

        // TODO: close position
        IPredyPool.TradeResult memory tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                insurancePool.pairId,
                positionId,
                -userPosition.positionAmount,
                -userPosition.positionAmountSqrt,
                abi.encode(
                    CallbackData(
                        CallbackSource.LIQUIDATION, msg.sender, userPosition.owner, userPosition.filler, 0, false
                    )
                )
            ),
            settlementData
        );

        // TODO: check slippage
        _checkPrice(tradeResult, _LIQ_SLIPPAGE);

        _sendMarginToUser(positionId, 0);
    }

    function confirmLiquidation(uint256 positionId, ISettlement.SettlementData memory settlementData) external {
        UserPosition storage userPosition = userPositions[positionId];

        // TODO: check liquidated
        // TODO: in case of partial liquidation
        DataType.Vault memory vault = _predyPool.getVault(positionId);

        // vault has positions but has no cover positions
        require(
            vault.openPosition.perp.amount.abs() < userPosition.positionAmount.abs()
                || vault.openPosition.sqrtPerp.amount.abs() < userPosition.positionAmountSqrt.abs()
        );

        if (vault.margin < userPosition.marginAmount + userPosition.assuranceMargin) {
            if (vault.margin <= userPosition.assuranceMargin) {
                userPosition.marginAmount = 0;
                userPosition.assuranceMargin = vault.margin;
            } else {
                userPosition.marginAmount = vault.margin - userPosition.assuranceMargin;
            }
        }

        if (vault.openPosition.perp.amount > 0 || vault.openPosition.sqrtPerp.amount > 0) {
            IPredyPool.TradeResult memory tradeResult = _predyPool.trade(
                IPredyPool.TradeParams(
                    userPosition.pairId,
                    positionId,
                    -vault.openPosition.perp.amount,
                    -vault.openPosition.sqrtPerp.amount,
                    abi.encode(
                        CallbackData(
                            CallbackSource.LIQUIDATION, msg.sender, userPosition.owner, userPosition.filler, 0, false
                        )
                    )
                ),
                settlementData
            );

            _checkPrice(tradeResult, _LIQ_SLIPPAGE);
        }

        _predyPool.updateMargin(positionId, -vault.margin);

        // TODO: clear userPosition
        userPosition.positionAmount = 0;
        userPosition.positionAmountSqrt = 0;

        _sendMarginToUser(positionId, 0);
    }

    // Private Functions

    function initFillerPool(uint256 pairId, address fillerAddress) internal returns (address) {
        InsurancePool storage fillerPool = insurancePools[fillerAddress][pairId];

        fillerPool.pairId = pairId;
        fillerPool.fillerAddress = fillerAddress;

        return fillerAddress;
    }

    function _sendMarginToUser(uint256 positionId, uint256 withdrawAmount) internal {
        UserPosition storage userPosition = userPositions[positionId];

        if (userPosition.positionAmount == 0 && userPosition.positionAmountSqrt == 0) {
            uint256 marginAmount = 0;

            if (userPosition.marginAmount > 0) {
                marginAmount = uint256(userPosition.marginAmount);

                userPosition.marginAmount = 0;
            }

            IERC20(_quoteTokenMap[userPosition.pairId]).transfer(userPosition.owner, marginAmount + withdrawAmount);
        } else {
            if (withdrawAmount > 0) {
                IERC20(_quoteTokenMap[userPosition.pairId]).transfer(userPosition.owner, withdrawAmount);
            }
        }
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

    function _updateBorrowFee(UserPosition storage userPosition) internal {
        InsurancePool storage filler = insurancePools[userPosition.filler][userPosition.pairId];

        uint256 elapsedTime = block.timestamp - userPosition.lastBorrowFeeCalculationTime;

        uint256 borrowFee = uint256(userPosition.assuranceMargin) * BORROW_FEE_RATE * elapsedTime / (365 days * 1e8);

        userPosition.marginAmount -= int256(borrowFee);
        filler.marginAmount += int256(borrowFee);

        userPosition.lastBorrowFeeCalculationTime = block.timestamp;
    }

    function isPositionSafe(UserPosition memory userPosition) internal view returns (bool) {
        (int256 minMargin, int256 vaultValue,) = calculateMinDeposit(userPosition);

        return vaultValue >= minMargin;
    }

    function calculateMinDeposit(UserPosition memory userPosition)
        internal
        view
        returns (int256 minMargin, int256 vaultValue, bool hasPosition)
    {
        PositionCalculator.PositionParams memory positionParams =
            _predyPool.getPositionWithUnrealizedFee(userPosition.id);

        int256 minValue;
        uint256 debtValue;

        uint256 indexPrice = _predyPool.getSqrtIndexPrice(userPosition.pairId);

        (minValue, vaultValue, debtValue, hasPosition) = PositionCalculator.calculateMinValue(
            userPosition.marginAmount,
            positionParams,
            indexPrice,
            // square root of 1%
            _RISK_RATIO
        );

        int256 minMinValue = SafeCast.toInt256(_MARGIN_RATIO_WITH_DEBT_SQUART * debtValue / 1e6);

        minMargin = vaultValue - minValue + minMinValue;

        if (hasPosition && minMargin < Constants.MIN_MARGIN_AMOUNT) {
            minMargin = Constants.MIN_MARGIN_AMOUNT;
        }
    }

    function _handleTradeResult(
        UserPosition storage userPosition,
        IPredyPool.TradeResult memory tradeResult,
        bool useInsuranceFund
    ) internal {
        tradeResult.payoff.perpPayoff = _roundAndAddToProtocolFee(userPosition, tradeResult.payoff.perpPayoff, 4);

        tradeResult.payoff.sqrtPayoff = _roundAndAddToProtocolFee(userPosition, tradeResult.payoff.sqrtPayoff, 4);

        tradeResult.fee = _roundAndAddToProtocolFee(userPosition, tradeResult.fee, 4);

        userPosition.marginAmount += tradeResult.payoff.perpPayoff + tradeResult.payoff.sqrtPayoff + tradeResult.fee;

        if (useInsuranceFund) {
            if (userPosition.marginAmount < 0) {
                int256 requiredMarginAmount = int256(-userPosition.marginAmount);
                // constraint: requiredMarginAmount > 0

                // TODO: check negative
                userPosition.assuranceMargin -= requiredMarginAmount;
            }
        } else {
            require(userPosition.marginAmount >= 0);
        }
    }

    error SlippageTooLarge();

    error OutOfAcceptablePriceRange();

    function _checkPrice(IPredyPool.TradeResult memory tradeResult, uint256 slippageTolerance) internal pure {
        uint256 sqrtTwap = tradeResult.sqrtTwap;
        uint256 twap = (sqrtTwap * sqrtTwap) >> Constants.RESOLUTION;

        if (tradeResult.averagePrice > 0) {
            // long
            if (twap * 1e4 / slippageTolerance > uint256(tradeResult.averagePrice)) {
                revert SlippageTooLarge();
            }
        } else if (tradeResult.averagePrice < 0) {
            // short
            if (twap * slippageTolerance / 1e4 < uint256(-tradeResult.averagePrice)) {
                revert SlippageTooLarge();
            }
        }

        if (
            tradeResult.sqrtPrice < sqrtTwap * 1e8 / _MAX_ACCEPTABLE_SQRT_PRICE_RANGE
                || sqrtTwap * _MAX_ACCEPTABLE_SQRT_PRICE_RANGE / 1e8 < tradeResult.sqrtPrice
        ) {
            revert OutOfAcceptablePriceRange();
        }
    }

    function _roundAndAddToProtocolFee(UserPosition storage userPosition, int256 _amount, uint8 _marginRoundedDecimal)
        internal
        returns (int256)
    {
        int256 rounded = _roundMargin(_amount, 10 ** _marginRoundedDecimal);

        if (_amount > rounded) {
            userPosition.assuranceMargin += _amount - rounded;
        }

        return rounded;
    }

    function _roundMargin(int256 _amount, uint256 _roundedDecimals) internal pure returns (int256) {
        if (_amount > 0) {
            return int256(FixedPointMathLib.mulDivDown(uint256(_amount), 1, _roundedDecimals) * _roundedDecimals);
        } else {
            return -int256(FixedPointMathLib.mulDivUp(uint256(-_amount), 1, _roundedDecimals) * _roundedDecimals);
        }
    }
}
