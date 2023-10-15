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
import "./libraries/Perp.sol";
import "./libraries/Constants.sol";
import "./libraries/DataType.sol";
import "forge-std/console.sol";

/**
 * @notice Provides perps to retail traders
 */
contract PerpMarket is IFillerMarket, BaseHookCallback {
    using ResolvedOrderLib for ResolvedOrder;
    using GeneralOrderLib for GeneralOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;
    using Math for int256;

    IPermit2 _permit2;
    address _quoteTokenAddress;

    struct Filler {
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
        uint256 fillerMarketId;
        address owner;
        int256 positionAmount;
        int256 entryValue;
        int256 marginAmount;
        int256 cumulativeFundingRates;
    }

    struct PerpTradeResult {
        int256 tradeAmount;
        int256 entryUpdate;
        int256 payoff;
    }

    error CallerIsNotFiller();

    error MarginIsNegative();

    error FillerPoolIsNotSafe();

    uint64 public positionCounts;

    mapping(uint256 vaultId => UserPosition) public userPositions;

    mapping(uint256 => Filler) public fillers;

    modifier onlyFiller(uint256 fillerPoolId) {
        if (fillers[fillerPoolId].fillerAddress != msg.sender) revert CallerIsNotFiller();
        _;
    }

    constructor(IPredyPool _predyPool, address quoteTokenAddress, address permit2Address)
        BaseHookCallback(_predyPool)
    {
        _quoteTokenAddress = quoteTokenAddress;
        _permit2 = IPermit2(permit2Address);

        positionCounts = 1;
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
     * @notice Deposits margin to the filler margin pool.
     * @param fillerPoolId The id of filler pool
     * @param depositAmount The amount to deposit
     */
    function depositToFillerPool(uint256 fillerPoolId, uint256 depositAmount) external onlyFiller(fillerPoolId) {
        require(depositAmount > 0);

        IERC20(_quoteTokenAddress).transferFrom(msg.sender, address(this), depositAmount);

        fillers[fillerPoolId].marginAmount += int256(depositAmount);
        // marginAmount increase by funding fee
        // marginAmount decrease by liquidation

        IERC20(_quoteTokenAddress).approve(address(_predyPool), depositAmount);

        _predyPool.updateMargin(fillers[fillerPoolId].vaultId, int256(depositAmount));
    }

    /**
     * @notice Withdraws margin from the filler margin pool.
     * @param fillerPoolId The id of filler pool
     * @param withdrawAmount The amount to withdraw
     */
    function withdrawFromFillerPool(uint256 fillerPoolId, uint256 withdrawAmount) external onlyFiller(fillerPoolId) {
        require(withdrawAmount > 0);

        _predyPool.updateMargin(fillers[fillerPoolId].vaultId, -int256(withdrawAmount));

        fillers[fillerPoolId].marginAmount -= int256(withdrawAmount);

        checkFillerPoolIsSafe(fillerPoolId);

        IERC20(_quoteTokenAddress).transfer(msg.sender, withdrawAmount);
    }

    /**
     * @notice Verifies signature of the order and executes trade
     * @param fillerPoolId The id of filler pool
     * @param order The order signed by trader
     * @param settlementData The route of settlement created by filler
     * @dev Fillers can open position and anyone can close position
     */
    function executeOrder(
        uint256 fillerPoolId,
        SignedOrder memory order,
        ISettlement.SettlementData memory settlementData
    ) external returns (PerpTradeResult memory perpTradeResult) {
        (GeneralOrder memory generalOrder, ResolvedOrder memory resolvedOrder) =
            GeneralOrderLib.resolve(order, _quoteTokenAddress);

        // validate resolved order and verify for permit2
        // transfer token from trader to the contract
        _verifyOrder(resolvedOrder);

        // Check if position needs to be created or updated
        if (generalOrder.positionId == 0) {
            // Creates position
            generalOrder.positionId = positionCounts;

            userPositions[generalOrder.positionId].owner = generalOrder.info.trader;
            userPositions[generalOrder.positionId].fillerMarketId = fillerPoolId;

            positionCounts++;
        } else {
            // Updates position
            UserPosition memory userPosition = userPositions[generalOrder.positionId];
            if (generalOrder.info.trader != userPosition.owner) {
                revert IFillerMarket.SignerIsNotVaultOwner();
            }

            // TODO: check pairId
            require(generalOrder.pairId == fillers[userPosition.fillerMarketId].pairId);
        }

        updateFundingFee(fillers[fillerPoolId], userPositions[generalOrder.positionId]);

        IPredyPool.TradeResult memory tradeResult;

        (perpTradeResult, tradeResult) = coverPosition(
            fillers[fillerPoolId],
            generalOrder.positionId,
            generalOrder.tradeAmount,
            generalOrder.marginAmount,
            settlementData
        );

        checkFillerPoolIsSafe(fillerPoolId);

        // Validate the trade
        IOrderValidator(generalOrder.validatorAddress).validate(generalOrder, tradeResult);

        userPositions[generalOrder.positionId].marginAmount += generalOrder.marginAmount;

        require(
            calculatePositionValue(
                userPositions[generalOrder.positionId], _predyPool.getSqrtIndexPrice(generalOrder.pairId)
            ),
            "SAFE"
        );

        // TODO: deposit user margin to the vault
        sendMarginToUser(generalOrder.positionId, generalOrder.marginAmount);

        return perpTradeResult;
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
        Filler storage fillerPool = fillers[userPosition.fillerMarketId];

        updateFundingFee(fillerPool, userPosition);

        // check vault is danger
        require(!calculatePositionValue(userPosition, _predyPool.getSqrtIndexPrice(fillerPool.pairId)), "NOT SAFE");

        coverPosition(fillerPool, positionId, -userPosition.positionAmount, 0, settlementData);

        // TODO: - filler margin

        sendMarginToUser(positionId, 0);
    }

    function confirmLiquidation(uint256 fillerPoolId) external {
        Filler storage filler = fillers[fillerPoolId];
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

    function close(uint256 fillerPoolId, uint64 positionId) external returns (PerpTradeResult memory perpTradeResult) {
        Filler storage filler = fillers[fillerPoolId];

        require(filler.isLiquidated);

        UserPosition storage userPosition = userPositions[positionId];

        uint256 price = filler.liquidationPrice * filler.liquidationPrice / Constants.Q96;

        int256 tradeAmount = -userPosition.positionAmount;

        int256 quoteAmount = -tradeAmount * int256(price) / int256(Constants.Q96);

        perpTradeResult = performTradePostProcessing(filler, positionId, tradeAmount, quoteAmount);

        // all positions have been processed for settlement
        if (filler.totalPosition.totalLongAmount == 0 && filler.totalPosition.totalShortAmount == 0) {
            filler.isLiquidated = false;
        }
    }

    // Private Functions

    function initFillerPool(uint256 pairId, address fillerAddress) internal returns (uint256) {
        uint256 vaultId = _predyPool.createVault(0, pairId);

        Filler storage fillerPool = fillers[vaultId];

        fillerPool.vaultId = vaultId;
        fillerPool.pairId = pairId;
        fillerPool.fillerAddress = fillerAddress;
        fillerPool.lastFundingRateCalculationTime = block.timestamp;
        fillerPool.isLiquidated = false;

        return vaultId;
    }

    function sendMarginToUser(uint64 positionId, int256 withdrawAmount) internal {
        UserPosition storage userPosition = userPositions[positionId];

        if (userPosition.positionAmount == 0) {
            if (userPosition.marginAmount > 0) {
                uint256 marginAmount = uint256(userPosition.marginAmount);

                // TODO: withdraw user margin from the vault

                userPosition.marginAmount = 0;

                IERC20(_quoteTokenAddress).transfer(userPosition.owner, marginAmount);
            } else if (userPosition.marginAmount < 0) {
                // filler should cover negative margin
                fillers[userPosition.fillerMarketId].marginAmount += userPosition.marginAmount;

                // TODO: What happens if fillers[userPosition.fillerMarketId].marginAmount < 0

                userPosition.marginAmount = 0;
            }
        } else {
            if (withdrawAmount < 0) {
                IERC20(_quoteTokenAddress).transfer(userPosition.owner, uint256(-withdrawAmount));
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
            GeneralOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    function updateFundingFee(Filler storage filler, UserPosition storage userPosition) internal {
        filler.fundingRateGrobalGrowth +=
            getFundingRate(filler) * int256(block.timestamp - filler.lastFundingRateCalculationTime) / int256(365 days);

        filler.lastFundingRateCalculationTime = block.timestamp;

        int256 fundingFee = (filler.fundingRateGrobalGrowth - userPosition.cumulativeFundingRates)
            * userPosition.positionAmount / int256(Constants.Q96);

        userPosition.cumulativeFundingRates = filler.fundingRateGrobalGrowth;

        userPosition.marginAmount += fundingFee;

        // TODO: +- fee to filler margin
        filler.marginAmount += (filler.fundingRateGrobalGrowth - filler.fillercumulativeFundingRates)
            * (int256(filler.totalPosition.totalLongAmount) - int256(filler.totalPosition.totalShortAmount))
            / int256(Constants.Q96);

        filler.fillercumulativeFundingRates = filler.fundingRateGrobalGrowth;
    }

    function getFundingRate(Filler memory filler) internal view returns (int256) {
        uint256 sqrtPrice = _predyPool.getSqrtPrice(filler.pairId);
        uint256 price = sqrtPrice * sqrtPrice / Constants.Q96;

        // TODO: Quote Token per Base Token
        if (filler.totalPosition.totalLongAmount > filler.totalPosition.totalShortAmount) {
            return int256(price) * 12 / 100;
        } else {
            return -int256(price) * 12 / 100;
        }
    }

    function coverPosition(
        Filler storage filler,
        uint256 positionId,
        int256 tradeAmount,
        int256 marginAmount,
        ISettlement.SettlementData memory settlementData
    ) internal returns (PerpTradeResult memory perpTradeResult, IPredyPool.TradeResult memory tradeResult) {
        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(filler.pairId, filler.vaultId, tradeAmount, 0, abi.encode(marginAmount)),
            settlementData
        );

        // TODO: unrequired
        // filler.vaultId = tradeResult.vaultId;

        perpTradeResult = performTradePostProcessing(
            filler, positionId, tradeAmount, tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff
        );
    }

    function performTradePostProcessing(
        Filler storage filler,
        uint256 positionId,
        int256 tradeAmount,
        int256 quoteAmount
    ) internal returns (PerpTradeResult memory perpTradeResult) {
        UserPosition storage userPosition = userPositions[positionId];

        perpTradeResult.tradeAmount = tradeAmount;

        (perpTradeResult.entryUpdate, perpTradeResult.payoff) =
            Perp.calculateEntry(userPosition.positionAmount, userPosition.entryValue, tradeAmount, quoteAmount);

        userPosition.entryValue += perpTradeResult.entryUpdate;

        updateLongShort(filler, userPosition.positionAmount, tradeAmount);

        userPosition.positionAmount += tradeAmount;
        userPosition.marginAmount += perpTradeResult.payoff;

        //
        userPosition.cumulativeFundingRates = filler.fundingRateGrobalGrowth;
    }

    function updateLongShort(Filler storage filler, int256 positionAmount, int256 tradeAmount) internal {
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

    function calculatePositionValue(UserPosition memory userPosition, uint256 sqrtPrice) internal pure returns (bool) {
        int256 price = int256((sqrtPrice * sqrtPrice) >> Constants.RESOLUTION);

        int256 value = userPosition.marginAmount + userPosition.positionAmount * price / int256(Constants.Q96)
            - userPosition.entryValue;
        int256 min = userPosition.positionAmount * price / int256(Constants.Q96 * 50);

        return value >= min;
    }

    /**
     * @notice Calculates filler minMargin
     * longPosition * price * (R - 1) / (R)
     * shortPosition * price * (R - 1)
     */
    function calculateFillerMinMargin(uint256 fillerPoolId, uint256 sqrtPrice) internal view returns (int256) {
        Filler memory filler = fillers[fillerPoolId];
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

    function checkFillerPoolIsSafe(uint256 fillerPoolId) internal view {
        Filler memory filler = fillers[fillerPoolId];

        IPredyPool.VaultStatus memory vaultStatus = _predyPool.getVaultStatus(fillerPoolId);

        // fillerPoolId is vaultId
        uint256 price = _predyPool.getSqrtIndexPrice(filler.pairId);

        if (filler.marginAmount < 0) {
            revert MarginIsNegative();
        }

        if (vaultStatus.vaultValue < calculateFillerMinMargin(fillerPoolId, price)) {
            revert FillerPoolIsNotSafe();
        }
    }
}
