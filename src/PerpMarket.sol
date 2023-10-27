// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@solmate/src/utils/FixedPointMathLib.sol";
import "./interfaces/IPredyPool.sol";
import "./interfaces/IFillerMarket.sol";
import "./interfaces/IOrderValidator.sol";
import "./base/BaseHookCallback.sol";
import "./libraries/orders/Permit2Lib.sol";
import "./libraries/orders/ResolvedOrder.sol";
import "./libraries/orders/PerpOrder.sol";
import "./libraries/math/Math.sol";
import "./libraries/Perp.sol";
import "./libraries/Constants.sol";
import "./libraries/DataType.sol";
import "./lens/PredyPoolQuoter.sol";
// import "forge-std/console.sol";

/**
 * @notice Provides perps to retail traders
 */
contract PerpMarket is IFillerMarket, BaseHookCallback {
    using ResolvedOrderLib for ResolvedOrder;
    using PerpOrderLib for PerpOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;
    using Math for int256;

    IPermit2 _permit2;

    struct InsurancePool {
        uint256 vaultId;
        uint256 pairId;
        address fillerAddress;
        int256 marginAmount;
        int256 fillercumulativeFundingRates;
        int256 fundingRateGrobalGrowth;
        uint256 lastFundingRateCalculationTime;
        TotalPosition totalPosition;
        bool isLiquidated;
        uint256 liquidationPrice;
    }

    struct TotalPosition {
        uint256 totalLongAmount;
        uint256 totalShortAmount;
    }

    struct UserPosition {
        uint256 id;
        uint256 fillerMarketId;
        address owner;
        int256 positionAmount;
        int256 entryValue;
        int256 marginAmount;
        int256 cumulativeFundingRates;
    }

    struct PerpTradeResult {
        int256 entryUpdate;
        int256 payoff;
    }

    error CallerIsNotFiller();

    error MarginIsNegative();

    error UserMarginIsNegative();

    error UserPositionIsNotSafe();

    error UserPositionIsNotDanger();

    error FillerPoolIsNotSafe();

    error SlippageTooLarge();

    uint256 public positionCount;

    mapping(uint256 vaultId => UserPosition) public userPositions;

    mapping(uint256 => InsurancePool) public insurancePools;

    event PositionUpdated(uint256 positionId, uint256 fillerMarketId, int256 tradeAmount, PerpTradeResult tradeResult);

    event FundingPayment(uint256 positionId, uint256 fillerMarketId, int256 fundingFee, int256 fillerFundingFee);

    modifier onlyFiller(uint256 fillerPoolId) {
        if (insurancePools[fillerPoolId].fillerAddress != msg.sender) revert CallerIsNotFiller();
        _;
    }

    constructor(IPredyPool _predyPool, address permit2Address) BaseHookCallback(_predyPool) {
        _permit2 = IPermit2(permit2Address);

        positionCount = 1;
    }

    /**
     * @notice Registers a new filler.
     */
    function addFillerPool(uint256 pairId) external returns (uint256) {
        return initFillerPool(pairId, msg.sender);
    }

    /**
     * @dev Callback for Predy pool.
     */
    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallback) onlyPredyPool {}

    /**
     * @notice Deposits margin to the insurance pool.
     * @param fillerPoolId The id of filler pool
     * @param depositAmount The amount to deposit
     */
    function depositToInsurancePool(uint256 fillerPoolId, uint256 depositAmount) external onlyFiller(fillerPoolId) {
        require(depositAmount > 0);

        address quoteTokenAddress = _quoteTokenMap[insurancePools[fillerPoolId].pairId];

        IERC20(quoteTokenAddress).transferFrom(msg.sender, address(this), depositAmount);

        insurancePools[fillerPoolId].marginAmount += int256(depositAmount);

        IERC20(quoteTokenAddress).approve(address(_predyPool), depositAmount);

        _predyPool.updateMargin(insurancePools[fillerPoolId].vaultId, int256(depositAmount));
    }

    /**
     * @notice Withdraws margin from the insurance pool.
     * @param fillerPoolId The id of filler pool
     * @param withdrawAmount The amount to withdraw
     */
    function withdrawFromInsurancePool(uint256 fillerPoolId, uint256 withdrawAmount)
        external
        onlyFiller(fillerPoolId)
    {
        require(withdrawAmount > 0);

        _predyPool.updateMargin(insurancePools[fillerPoolId].vaultId, -int256(withdrawAmount));

        insurancePools[fillerPoolId].marginAmount -= int256(withdrawAmount);

        validateFillerPoolSafety(fillerPoolId);

        TransferHelper.safeTransfer(_quoteTokenMap[insurancePools[fillerPoolId].pairId], msg.sender, withdrawAmount);
    }

    /**
     * @notice Verifies signature of the order and executes trade
     * @dev Fillers can open position and anyone can close position
     * @param fillerPoolId The id of filler pool
     * @param order The order signed by trader
     * @param settlementData The route of settlement created by filler
     */
    function executeOrder(
        uint256 fillerPoolId,
        SignedOrder memory order,
        ISettlement.SettlementData memory settlementData
    ) external returns (PerpTradeResult memory perpTradeResult) {
        PerpOrder memory perpOrder = abi.decode(order.order, (PerpOrder));
        ResolvedOrder memory resolvedOrder = PerpOrderLib.resolve(perpOrder, order.sig);

        require(_quoteTokenMap[perpOrder.pairId] != address(0));
        require(perpOrder.entryTokenAddress == _quoteTokenMap[perpOrder.pairId]);

        // validate resolved order and verify for permit2
        // transfer token from trader to the contract
        _verifyOrder(resolvedOrder);

        // deposit margin to the vault if required
        if (perpOrder.marginAmount > 0) {
            IERC20(perpOrder.entryTokenAddress).approve(address(_predyPool), uint256(perpOrder.marginAmount));
            _predyPool.updateMargin(insurancePools[fillerPoolId].vaultId, perpOrder.marginAmount);
        }

        // Check if position needs to be created or updated
        if (perpOrder.positionId == 0) {
            // Creates position
            perpOrder.positionId = positionCount;

            userPositions[perpOrder.positionId].id = perpOrder.positionId;
            userPositions[perpOrder.positionId].owner = perpOrder.info.trader;
            userPositions[perpOrder.positionId].fillerMarketId = fillerPoolId;

            positionCount++;
        } else {
            // Updates position
            UserPosition memory userPosition = userPositions[perpOrder.positionId];
            if (perpOrder.info.trader != userPosition.owner) {
                revert IFillerMarket.SignerIsNotVaultOwner();
            }

            require(perpOrder.pairId == insurancePools[userPosition.fillerMarketId].pairId);
        }

        // Update the funding fees for the user position in the filler pool
        updateFundingFee(insurancePools[fillerPoolId], userPositions[perpOrder.positionId]);

        IPredyPool.TradeResult memory tradeResult;

        // Execute the trade for the user position in the filler pool
        (perpTradeResult, tradeResult) = coverPosition(
            insurancePools[fillerPoolId],
            perpOrder.positionId,
            perpOrder.tradeAmount,
            perpOrder.marginAmount,
            settlementData
        );

        validateFillerPoolSafety(fillerPoolId);

        // Validate the trade
        IPerpOrderValidator(perpOrder.validatorAddress).validate(perpOrder, tradeResult);

        userPositions[perpOrder.positionId].marginAmount += perpOrder.marginAmount;

        if (userPositions[perpOrder.positionId].marginAmount < 0) {
            revert UserMarginIsNegative();
        }

        if (!isPositionSafe(userPositions[perpOrder.positionId], _predyPool.getSqrtIndexPrice(perpOrder.pairId))) {
            revert UserPositionIsNotSafe();
        }

        sendMarginToUser(perpOrder.positionId, perpOrder.marginAmount < 0 ? uint256(-perpOrder.marginAmount) : 0);

        emit PositionUpdated(perpOrder.positionId, fillerPoolId, perpOrder.tradeAmount, perpTradeResult);

        return perpTradeResult;
    }

    function quoteExecuteOrder(
        PerpOrder memory perpOrder,
        ISettlement.SettlementData memory settlementData,
        PredyPoolQuoter quoter
    ) external {
        PerpTradeResult memory perpTradeResult;

        if (perpOrder.positionId == 0) {
            perpOrder.positionId = positionCount;
        }

        UserPosition memory userPosition = userPositions[perpOrder.positionId];

        // Execute the trade for the user position in the filler pool
        IPredyPool.TradeResult memory tradeResult = quoter.quoteTrade(
            IPredyPool.TradeParams(perpOrder.pairId, perpOrder.positionId, perpOrder.tradeAmount, 0, bytes("")),
            settlementData
        );

        (perpTradeResult.entryUpdate, perpTradeResult.payoff) = Perp.calculateEntry(
            userPosition.positionAmount,
            userPosition.entryValue,
            perpOrder.tradeAmount,
            tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff
        );

        revertTradeResult(perpTradeResult);
    }

    function quoteUserPosition(uint256 positionId) external {
        UserPosition storage userPosition = userPositions[positionId];

        updateFundingFee(insurancePools[userPosition.fillerMarketId], userPosition);

        revertUserPosition(userPosition);
    }

    function revertTradeResult(PerpTradeResult memory perpTradeResult) internal pure {
        bytes memory data = abi.encode(perpTradeResult);

        assembly {
            revert(add(32, data), mload(data))
        }
    }

    function revertUserPosition(UserPosition memory userPosition) internal pure {
        bytes memory data = abi.encode(userPosition);

        assembly {
            revert(add(32, data), mload(data))
        }
    }

    function depositMargin(uint256 marginAmount) external {}

    function withdrawMargin(uint256 marginAmount) external {}

    /**
     * @notice Executes liquidation call for the position
     * @dev Anyone can liquidate position but only filler can cover negative margin
     * @param positionId The id of position
     * @param settlementData The route of settlement created by liquidator
     */
    function execLiquidationCall(uint256 positionId, ISettlement.SettlementData memory settlementData) external {
        UserPosition storage userPosition = userPositions[positionId];
        InsurancePool storage fillerPool = insurancePools[userPosition.fillerMarketId];

        updateFundingFee(fillerPool, userPosition);

        uint256 indexPrice = _predyPool.getSqrtIndexPrice(fillerPool.pairId);

        // check vault is danger
        if (isPositionSafe(userPosition, indexPrice)) {
            revert UserPositionIsNotDanger();
        }

        int256 tradeAmount = -userPosition.positionAmount;

        (PerpTradeResult memory perpTradeResult,) =
            coverPosition(fillerPool, positionId, tradeAmount, 0, settlementData);

        {
            // TODO: compare indexPrice and closePrice
            int256 closePrice =
                int256(Math.abs(perpTradeResult.entryUpdate + perpTradeResult.payoff) * Constants.Q96) / tradeAmount;
            uint256 slippageTolerance = 10050;

            if (closePrice > 0) {
                // long
                if (indexPrice * 1e4 / slippageTolerance > uint256(closePrice)) {
                    revert SlippageTooLarge();
                }
            } else if (closePrice < 0) {
                // short
                if (indexPrice * slippageTolerance / 1e4 < uint256(-closePrice)) {
                    revert SlippageTooLarge();
                }
            }
        }

        handlePositionMargin(positionId, fillerPool.pairId);
    }

    /**
     * @dev Confirms the liquidation for a given filler pool.
     * @param fillerPoolId The id of the filler pool.
     */
    function confirmLiquidation(uint256 fillerPoolId) external {
        InsurancePool storage filler = insurancePools[fillerPoolId];

        // TODO: check liquidated
        IPredyPool.VaultStatus memory vaultStatus = _predyPool.getVaultStatus(filler.vaultId);

        require(
            vaultStatus.minMargin == 0
                && (filler.totalPosition.totalLongAmount > 0 || filler.totalPosition.totalShortAmount > 0)
        );

        uint256 sqrtPrice = _predyPool.getSqrtIndexPrice(filler.pairId);

        filler.liquidationPrice = sqrtPrice;

        filler.isLiquidated = true;
    }

    /**
     * @dev Closes the user's position and returns the trade result after processing.
     * @param fillerPoolId Thss id of the filler pool.
     * @param positionId Ths id of the user position to be closed.
     * @return perpTradeResult The result of the processed trade.
     */
    function close(uint256 fillerPoolId, uint256 positionId)
        external
        returns (PerpTradeResult memory perpTradeResult)
    {
        InsurancePool storage filler = insurancePools[fillerPoolId];

        require(filler.isLiquidated, "filler is not liquidated");

        UserPosition storage userPosition = userPositions[positionId];

        uint256 price = filler.liquidationPrice * filler.liquidationPrice / Constants.Q96;

        int256 tradeAmount = -userPosition.positionAmount;

        int256 quoteAmount = -tradeAmount * int256(price) / int256(Constants.Q96);

        perpTradeResult = performTradePostProcessing(filler, positionId, tradeAmount, quoteAmount);

        sendMarginToUser(positionId, 0);

        // all positions have been processed for settlement
        if (filler.totalPosition.totalLongAmount == 0 && filler.totalPosition.totalShortAmount == 0) {
            filler.isLiquidated = false;
        }
    }

    // Private Functions

    function initFillerPool(uint256 pairId, address fillerAddress) internal returns (uint256) {
        uint256 vaultId = _predyPool.createVault(pairId);

        InsurancePool storage fillerPool = insurancePools[vaultId];

        fillerPool.vaultId = vaultId;
        fillerPool.pairId = pairId;
        fillerPool.fillerAddress = fillerAddress;
        fillerPool.lastFundingRateCalculationTime = block.timestamp;
        fillerPool.isLiquidated = false;

        return vaultId;
    }

    function sendMarginToUser(uint256 positionId, uint256 withdrawAmount) internal {
        UserPosition storage userPosition = userPositions[positionId];

        if (userPosition.positionAmount == 0) {
            uint256 marginAmount = 0;

            if (userPosition.marginAmount > 0) {
                marginAmount = uint256(userPosition.marginAmount);

                // TODO: withdraw user margin from the vault

                userPosition.marginAmount = 0;
            }

            transferMargin(userPosition, marginAmount + withdrawAmount);
        } else {
            if (withdrawAmount > 0) {
                transferMargin(userPosition, withdrawAmount);
            }
        }
    }

    function transferMargin(UserPosition memory userPosition, uint256 marginAmount) internal {
        InsurancePool memory filler = insurancePools[userPosition.fillerMarketId];

        _predyPool.updateMargin(filler.vaultId, -int256(marginAmount));

        TransferHelper.safeTransfer(_quoteTokenMap[filler.pairId], userPosition.owner, marginAmount);
    }

    function handlePositionMargin(uint256 positionId, uint256 pairId) internal {
        UserPosition storage userPosition = userPositions[positionId];

        if (userPosition.positionAmount == 0) {
            if (userPosition.marginAmount > 0) {
                uint256 marginAmount = uint256(userPosition.marginAmount);

                // TODO: withdraw user margin from the vault

                userPosition.marginAmount = 0;

                transferMargin(userPosition, marginAmount);
            } else if (userPosition.marginAmount < 0) {
                InsurancePool storage filler = insurancePools[userPosition.fillerMarketId];

                // TODO: if caller is filler then filler should cover negative margin
                // if not user margin must be grater than 0
                if (msg.sender == filler.fillerAddress) {
                    filler.marginAmount += userPosition.marginAmount;

                    // TODO: What happens if filler.marginAmount < 0
                    require(filler.marginAmount >= 0);

                    userPosition.marginAmount = 0;
                } else {
                    uint256 requiredMargin = uint256(-userPosition.marginAmount);

                    userPosition.marginAmount = 0;

                    IERC20(_quoteTokenMap[pairId]).transferFrom(msg.sender, address(this), requiredMargin);

                    IERC20(_quoteTokenMap[pairId]).approve(address(_predyPool), requiredMargin);
                    _predyPool.updateMargin(filler.vaultId, int256(requiredMargin));
                }
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
            PerpOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    /**
     * @dev Updates the funding fee for the user and filler based on their positions and the global growth rate.
     * @param filler The filler's position data.
     * @param userPosition The user's position data.
     */
    function updateFundingFee(InsurancePool storage filler, UserPosition storage userPosition) internal {
        filler.fundingRateGrobalGrowth +=
            getFundingRate(filler) * int256(block.timestamp - filler.lastFundingRateCalculationTime) / int256(365 days);

        // Update the timestamp for last funding rate calculation
        filler.lastFundingRateCalculationTime = block.timestamp;

        // Calculate user's funding fee
        int256 fundingFee = (filler.fundingRateGrobalGrowth - userPosition.cumulativeFundingRates)
            * userPosition.positionAmount / int256(Constants.Q96);

        fundingFee = _roundAndAddToProtocolFee(filler, fundingFee, 4);
        userPosition.marginAmount += fundingFee;

        userPosition.cumulativeFundingRates = filler.fundingRateGrobalGrowth;

        // Calculate filler's funding fee
        int256 fillerFundingFee = (filler.fundingRateGrobalGrowth - filler.fillercumulativeFundingRates)
            * (int256(filler.totalPosition.totalShortAmount) - int256(filler.totalPosition.totalLongAmount))
            / int256(Constants.Q96);

        filler.marginAmount += fillerFundingFee;

        filler.fillercumulativeFundingRates = filler.fundingRateGrobalGrowth;

        // Emitting an event for the funding payment
        emit FundingPayment(userPosition.id, userPosition.fillerMarketId, fundingFee, fillerFundingFee);
    }

    /**
     * @dev Calculates the funding rate based on the total position and market price.
     * @param filler The filler's position data.
     * @return fundingRate The calculated funding rate.
     */
    function getFundingRate(InsurancePool memory filler) internal view returns (int256 fundingRate) {
        uint256 sqrtPrice = _predyPool.getSqrtPrice(filler.pairId);
        uint256 price = sqrtPrice * sqrtPrice / Constants.Q96;

        fundingRate = int256(price) * 12 / 100;

        if (filler.totalPosition.totalLongAmount > filler.totalPosition.totalShortAmount) {
            return fundingRate;
        } else {
            return -fundingRate;
        }
    }

    function coverPosition(
        InsurancePool storage filler,
        uint256 positionId,
        int256 tradeAmount,
        int256 marginAmount,
        ISettlement.SettlementData memory settlementData
    ) internal returns (PerpTradeResult memory perpTradeResult, IPredyPool.TradeResult memory tradeResult) {
        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(filler.pairId, filler.vaultId, tradeAmount, 0, abi.encode(marginAmount)),
            settlementData
        );

        filler.marginAmount += tradeResult.fee;

        perpTradeResult = performTradePostProcessing(
            filler, positionId, tradeAmount, tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff
        );
    }

    function performTradePostProcessing(
        InsurancePool storage filler,
        uint256 positionId,
        int256 tradeAmount,
        int256 quoteAmount
    ) internal returns (PerpTradeResult memory perpTradeResult) {
        UserPosition storage userPosition = userPositions[positionId];

        (perpTradeResult.entryUpdate, perpTradeResult.payoff) =
            Perp.calculateEntry(userPosition.positionAmount, userPosition.entryValue, tradeAmount, quoteAmount);

        userPosition.entryValue += perpTradeResult.entryUpdate;

        updateLongShort(filler, userPosition.positionAmount, tradeAmount);

        userPosition.positionAmount += tradeAmount;
        perpTradeResult.payoff = _roundAndAddToProtocolFee(filler, perpTradeResult.payoff, 4);
        userPosition.marginAmount += perpTradeResult.payoff;

        //
        userPosition.cumulativeFundingRates = filler.fundingRateGrobalGrowth;
    }

    function updateLongShort(InsurancePool storage filler, int256 positionAmount, int256 tradeAmount) internal {
        int256 openAmount;
        int256 closeAmount;

        if (positionAmount * tradeAmount >= 0) {
            openAmount = tradeAmount;
        } else {
            if (positionAmount.abs() >= tradeAmount.abs()) {
                closeAmount = tradeAmount;
            } else {
                openAmount = positionAmount + tradeAmount;
                closeAmount = -positionAmount;
            }
        }

        if (openAmount > 0) {
            filler.totalPosition.totalLongAmount += uint256(openAmount);
        }
        if (openAmount < 0) {
            filler.totalPosition.totalShortAmount += uint256(-openAmount);
        }
        if (closeAmount > 0) {
            filler.totalPosition.totalShortAmount -= uint256(closeAmount);
        }
        if (closeAmount < 0) {
            filler.totalPosition.totalLongAmount -= uint256(-closeAmount);
        }

        // only filler can open position
        if (openAmount != 0 && filler.fillerAddress != msg.sender) {
            revert CallerIsNotFiller();
        }
    }

    /**
     * @notice If position is safe return true, if not return false.
     */
    function isPositionSafe(UserPosition memory userPosition, uint256 sqrtPrice) internal pure returns (bool) {
        int256 price = int256((sqrtPrice * sqrtPrice) >> Constants.RESOLUTION);

        int256 value = userPosition.marginAmount + userPosition.positionAmount * price / int256(Constants.Q96)
            + userPosition.entryValue;
        int256 min = int256(Math.abs(userPosition.positionAmount)) * price / int256(Constants.Q96 * 50);

        // console.log(uint256(value), uint256(min), uint256(userPosition.entryValue));

        return value >= min;
    }

    /**
     * @notice Calculates filler minMargin
     * longPosition * price * (R - 1) / (R)
     * shortPosition * price * (R - 1)
     */
    function calculateFillerMinMargin(InsurancePool memory filler, uint256 sqrtPrice) internal view returns (int256) {
        Perp.PairStatus memory pairStatus = _predyPool.getPairStatus(filler.pairId);

        uint256 price = (sqrtPrice * sqrtPrice) >> Constants.RESOLUTION;

        if (filler.totalPosition.totalLongAmount > filler.totalPosition.totalShortAmount) {
            uint256 R = pairStatus.riskParams.riskRatio * pairStatus.riskParams.riskRatio / 1e8;

            uint256 rPrice = price * (R - 1e8) / R;

            return int256(filler.totalPosition.totalLongAmount * rPrice / Constants.Q96);
        } else {
            // short case
            uint256 R = pairStatus.riskParams.riskRatio * pairStatus.riskParams.riskRatio / 1e8;

            uint256 rPrice = price * (R - 1e8) / 1e8;

            return int256(filler.totalPosition.totalShortAmount * rPrice / Constants.Q96);
        }
    }

    function validateFillerPoolSafety(uint256 fillerPoolId) internal view {
        InsurancePool memory filler = insurancePools[fillerPoolId];

        // fillerPoolId is vaultId
        IPredyPool.VaultStatus memory vaultStatus = _predyPool.getVaultStatus(filler.vaultId);

        uint256 price = _predyPool.getSqrtIndexPrice(filler.pairId);

        if (filler.marginAmount < 0) {
            revert MarginIsNegative();
        }

        if (vaultStatus.vaultValue < calculateFillerMinMargin(filler, price)) {
            revert FillerPoolIsNotSafe();
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
