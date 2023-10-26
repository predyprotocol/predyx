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
 * @notice Provides leveraged perps to retail traders
 */
contract LeveragedGammaMarket is IFillerMarket, BaseHookCallback {
    using ResolvedOrderLib for ResolvedOrder;
    using GammaOrderLib for GammaOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;
    using Math for int256;

    IPermit2 _permit2;
    address _quoteTokenAddress;
    // 12%;
    uint256 public constant BORROW_FEE_RATE = 1200;
    // 0.1%
    uint256 internal constant _MARGIN_RATIO_WITH_DEBT_SQUART = 1000;
    // The square root of 1%
    uint256 internal constant _RISK_RATIO = 100498756;

    struct InsurancePool {
        uint256 pairId;
        address fillerAddress;
        int256 marginAmount;
        int256 fillercumulativeFundingRates;
        int256 fundingRateGrobalGrowth;
        uint256 lastFundingRateCalculationTime;
    }

    struct UserPosition {
        uint256 id;
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
        int256 marginAmountUpdate;
    }

    error CallerIsNotFiller();

    mapping(uint256 vaultId => UserPosition) public userPositions;

    mapping(address => InsurancePool) public insurancePools;

    modifier onlyFiller() {
        if (insurancePools[msg.sender].fillerAddress != msg.sender) revert CallerIsNotFiller();
        _;
    }

    constructor(IPredyPool _predyPool, address quoteTokenAddress, address permit2Address)
        BaseHookCallback(_predyPool)
    {
        _quoteTokenAddress = quoteTokenAddress;
        _permit2 = IPermit2(permit2Address);
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallback) onlyPredyPool {
        UserPosition storage userPosition = userPositions[tradeParams.vaultId];
        InsurancePool storage filler = insurancePools[userPosition.filler];

        CallbackData memory callbackData = abi.decode(tradeParams.extraData, (CallbackData));

        _updateMargin(filler, userPosition, callbackData, tradeResult.minMargin);
    }

    function _updateMargin(
        InsurancePool storage filler,
        UserPosition storage userPosition,
        CallbackData memory callbackData,
        int256 fillerMinDeposit
    ) internal {
        int256 margin = _predyPool.getVault(userPosition.id).margin;
        int256 currentAssuranceMargin = userPosition.assuranceMargin;

        if (callbackData.callbackSource == CallbackSource.TRADE) {
            int256 userMargin = margin - currentAssuranceMargin;

            require(userMargin + callbackData.marginAmountUpdate >= 0);

            userPosition.assuranceMargin = fillerMinDeposit;

            int256 diff = userMargin + fillerMinDeposit - currentAssuranceMargin;

            userPosition.marginAmount += callbackData.marginAmountUpdate;
            filler.marginAmount += diff;

            diff += callbackData.marginAmountUpdate;

            if (diff > 0) {
                IERC20(_getQuoteTokenAddress(filler.pairId)).transfer(address(_predyPool), uint256(diff));
            } else if (diff < 0) {
                _predyPool.take(true, address(this), uint256(-diff));
            }
        } else if (callbackData.callbackSource == CallbackSource.LIQUIDATION) {
            _predyPool.take(true, address(this), uint256(margin));
        }
    }

    function depositToInsurancePool(uint256 depositAmount) external onlyFiller {
        IERC20(_getQuoteTokenAddress(insurancePools[msg.sender].pairId)).transferFrom(
            msg.sender, address(this), depositAmount
        );

        insurancePools[msg.sender].marginAmount += int256(depositAmount);
    }

    function withdrawFromInsurancePool(uint256 withdrawAmount) external onlyFiller {
        insurancePools[msg.sender].marginAmount -= int256(withdrawAmount);

        IERC20(_getQuoteTokenAddress(insurancePools[msg.sender].pairId)).transfer(msg.sender, withdrawAmount);
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
                abi.encode(CallbackData(CallbackSource.TRADE, gammaOrder.marginAmount))
            ),
            settlementData
        );

        if (gammaOrder.positionId == 0) {
            userPositions[tradeResult.vaultId].id = gammaOrder.positionId;
            userPositions[tradeResult.vaultId].owner = gammaOrder.info.trader;

            _predyPool.updateRecepient(tradeResult.vaultId, gammaOrder.info.trader);
        } else {
            if (gammaOrder.info.trader != userPositions[tradeResult.vaultId].owner) {
                revert IFillerMarket.SignerIsNotVaultOwner();
            }
        }

        userPositions[tradeResult.vaultId].positionAmount += gammaOrder.tradeAmount;
        userPositions[tradeResult.vaultId].positionAmountSqrt += gammaOrder.tradeAmountSqrt;

        require(isPositionSafe(userPositions[tradeResult.vaultId]), "SAFE");

        // TODO: should have white list for validatorAddress?
        IOrderValidator(gammaOrder.validatorAddress).validate(gammaOrder, tradeResult);

        if (gammaOrder.marginAmount < 0) {
            IERC20(_quoteTokenMap[gammaOrder.pairId]).transfer(
                gammaOrder.info.trader, uint256(-gammaOrder.marginAmount)
            );
        }

        return tradeResult;
    }

    function depositMargin(uint256 marginAmount) external {}

    function withdrawMargin(uint256 marginAmount) external {}

    /**
     * @notice Executes liquidation call for the position
     * @param positionId The id of position
     * @param settlementData The route of settlement created by liquidator
     */
    function execLiquidationCall(uint64 positionId, ISettlement.SettlementData memory settlementData) external {
        UserPosition storage userPosition = userPositions[positionId];
        InsurancePool storage fillerPool = insurancePools[userPosition.filler];

        // check vault is danger
        require(!isPositionSafe(userPosition), "NOT SAFE");

        // TODO: close position
        _predyPool.trade(
            IPredyPool.TradeParams(
                fillerPool.pairId,
                positionId,
                -userPosition.positionAmount,
                -userPosition.positionAmountSqrt,
                abi.encode(CallbackData(CallbackSource.LIQUIDATION, 0))
            ),
            settlementData
        );

        // TODO: - filler margin

        sendMarginToUser(positionId, fillerPool.pairId);
    }

    function confirmLiquidation(uint256 vaultId) external {
        UserPosition storage userPosition = userPositions[vaultId];

        // TODO: check liquidated
        IPredyPool.VaultStatus memory vaultStatus = _predyPool.getVaultStatus(vaultId);

        // vault has positions but has no cover positions
        require(
            vaultStatus.minMargin == 0 && (userPosition.positionAmount != 0 || userPosition.positionAmountSqrt != 0)
        );

        DataType.Vault memory vault = _predyPool.getVault(vaultId);

        _predyPool.updateMargin(vaultId, -vault.margin);

        userPosition.positionAmount = 0;

        // TODO: clear userPosition
        InsurancePool storage filler = insurancePools[userPosition.filler];

        filler.marginAmount += vault.margin;
    }

    // Private Functions

    function initFillerPool(uint256 pairId, address fillerAddress) internal returns (uint256) {
        uint256 vaultId = _predyPool.createVault(pairId);

        InsurancePool storage fillerPool = insurancePools[fillerAddress];

        fillerPool.pairId = pairId;
        fillerPool.fillerAddress = fillerAddress;
        fillerPool.lastFundingRateCalculationTime = block.timestamp;

        return vaultId;
    }

    function sendMarginToUser(uint64 positionId, uint256 pairId) internal {
        UserPosition storage userPosition = userPositions[positionId];

        if (userPosition.positionAmount == 0) {
            if (userPosition.positionAmount == 0 && userPosition.marginAmount > 0) {
                uint256 marginAmount = uint256(userPosition.marginAmount);

                userPosition.marginAmount = 0;

                IERC20(_quoteTokenMap[pairId]).transfer(userPosition.owner, marginAmount);
            } else {
                // filler should cover negative margin
                insurancePools[userPosition.filler].marginAmount += userPosition.marginAmount;

                userPosition.marginAmount = 0;
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
        InsurancePool storage filler = insurancePools[userPosition.filler];

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

        uint256 indexPrice = _predyPool.getSqrtIndexPrice(insurancePools[userPosition.filler].pairId);

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

    function _roundAndAddToProtocolFee(InsurancePool storage filler, int256 _amount, uint8 _marginRoundedDecimal)
        internal
        returns (int256)
    {
        int256 rounded = _roundMargin(_amount, 10 ** _marginRoundedDecimal);

        if (_amount > rounded) {
            filler.marginAmount += _amount - rounded;
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
