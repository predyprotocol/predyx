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
    address _fillerAddress;

    struct UserPosition {
        uint64 pairId;
        address owner;
        int256 positionAmount;
        int256 entryValue;
        int256 marginAmount;
        int256 cumulativeFundingRates;
        int256 marginCoveredByFiller;
    }

    struct PerpTradeResult {
        int256 tradeAmount;
        int256 entryUpdate;
        int256 payoff;
    }

    error CallerIsNotFiller();

    mapping(uint256 vaultId => UserPosition) public userPositions;

    uint64 public positionCounts;
    uint256 public vaultId;

    int256 fundingRateGrobalGrowth;
    uint256 lastFundingRateCalculationTime;

    int256 fillerMarginAmount;
    int256 fillerCumulativeFundingRates;

    struct TotalPosition {
        uint256 totalLongAmount;
        uint256 totalShortAmount;
    }

    TotalPosition public totalPosition;

    constructor(
        IPredyPool _predyPool,
        address quoteTokenAddress,
        address permit2Address,
        address fillerAddress,
        uint256 pairId
    ) BaseHookCallback(_predyPool) {
        _quoteTokenAddress = quoteTokenAddress;
        _permit2 = IPermit2(permit2Address);
        _fillerAddress = fillerAddress;
        positionCounts = 1;

        vaultId = _predyPool.createVault(vaultId, pairId);

        lastFundingRateCalculationTime = block.timestamp;
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallback) onlyPredyPool {}

    /**
     * @notice Verifies signature of the order and executes trade
     * @param order The order signed by trader
     * @param settlementData The route of settlement created by filler
     * @dev Fillers call this function
     */
    function executeOrder(SignedOrder memory order, ISettlement.SettlementData memory settlementData)
        external
        returns (PerpTradeResult memory perpTradeResult)
    {
        (GeneralOrder memory generalOrder, ResolvedOrder memory resolvedOrder) =
            GeneralOrderLib.resolve(order, _quoteTokenAddress);

        _verifyOrder(resolvedOrder);

        if (generalOrder.positionId == 0) {
            generalOrder.positionId = positionCounts;
            userPositions[generalOrder.positionId].owner = generalOrder.info.trader;
            userPositions[generalOrder.positionId].pairId = generalOrder.pairId;
            positionCounts++;
        } else {
            // TODO: check pairId
            if (generalOrder.info.trader != userPositions[generalOrder.positionId].owner) {
                revert IFillerMarket.SignerIsNotVaultOwner();
            }
        }

        updateFundingFee(userPositions[generalOrder.positionId]);

        IPredyPool.TradeResult memory tradeResult;

        (perpTradeResult, tradeResult) = coverPosition(
            generalOrder.pairId,
            generalOrder.positionId,
            generalOrder.tradeAmount,
            generalOrder.marginAmount,
            settlementData
        );

        // only filler can open position
        if (userPositions[generalOrder.positionId].positionAmount != 0 && msg.sender != _fillerAddress) {
            revert CallerIsNotFiller();
        }

        IOrderValidator(generalOrder.validatorAddress).validate(generalOrder, tradeResult);

        userPositions[generalOrder.positionId].marginAmount += generalOrder.marginAmount;

        require(
            calculatePositionValue(
                userPositions[generalOrder.positionId], _predyPool.getSqrtIndexPrice(generalOrder.pairId)
            ),
            "SAFE"
        );

        if (generalOrder.marginAmount < 0) {
            IERC20(_quoteTokenAddress).transfer(
                userPositions[generalOrder.positionId].owner, uint256(-generalOrder.marginAmount)
            );
        }

        sendMarginToUser(generalOrder.positionId);

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

        updateFundingFee(userPosition);

        // check vault is danger
        require(!calculatePositionValue(userPosition, _predyPool.getSqrtIndexPrice(userPosition.pairId)), "NOT SAFE");

        coverPosition(userPosition.pairId, positionId, -userPosition.positionAmount, 0, settlementData);

        // TODO: - filler margin

        sendMarginToUser(positionId);
    }

    function sendMarginToUser(uint64 positionId) internal {
        UserPosition storage userPosition = userPositions[positionId];

        if (userPosition.positionAmount == 0) {
            if (userPosition.positionAmount == 0 && userPosition.marginAmount > 0) {
                uint256 marginAmount = uint256(userPosition.marginAmount);

                userPosition.marginAmount = 0;

                IERC20(_quoteTokenAddress).transfer(userPosition.owner, marginAmount);
            } else {
                // filler should cover negative margin
                fillerMarginAmount += userPosition.marginAmount;

                userPosition.marginAmount = 0;
            }
        }
    }

    function depositToFillerPool(uint256 depositAmount) external {
        IERC20(_quoteTokenAddress).transferFrom(msg.sender, address(this), depositAmount);

        fillerMarginAmount += int256(depositAmount);

        IERC20(_quoteTokenAddress).approve(address(_predyPool), depositAmount);
        _predyPool.updateMargin(vaultId, int256(depositAmount));
    }

    function withdrawFromFillerPool(uint256 withdrawAmount) external {
        _predyPool.updateMargin(vaultId, -int256(withdrawAmount));

        fillerMarginAmount -= int256(withdrawAmount);

        checkFillerMinDeposit();

        IERC20(_quoteTokenAddress).transfer(msg.sender, withdrawAmount);
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

    function updateFundingFee(UserPosition storage userPosition) internal {
        fundingRateGrobalGrowth += getFundingRate(userPosition.pairId)
            * int256(block.timestamp - lastFundingRateCalculationTime) / int256(365 days);

        lastFundingRateCalculationTime = block.timestamp;

        int256 fundingFee = (fundingRateGrobalGrowth - userPosition.cumulativeFundingRates)
            * userPosition.positionAmount / int256(Constants.Q96);

        userPosition.cumulativeFundingRates = fundingRateGrobalGrowth;

        userPosition.marginAmount += fundingFee;

        // TODO: +- fee to filler margin
        fillerMarginAmount += (fundingRateGrobalGrowth - fillerCumulativeFundingRates)
            * (int256(totalPosition.totalLongAmount) - int256(totalPosition.totalShortAmount)) / int256(Constants.Q96);

        fillerCumulativeFundingRates = fundingRateGrobalGrowth;
    }

    function getFundingRate(uint256 pairId) internal view returns (int256) {
        uint256 sqrtPrice = _predyPool.getSqrtPrice(pairId);
        uint256 price = sqrtPrice * sqrtPrice / Constants.Q96;

        // TODO: Quote Token per Base Token
        if (totalPosition.totalLongAmount > totalPosition.totalShortAmount) {
            return int256(price) * 12 / 100;
        } else {
            return -int256(price) * 12 / 100;
        }
    }

    function coverPosition(
        uint64 pairId,
        uint256 positionId,
        int256 tradeAmount,
        int256 marginAmount,
        ISettlement.SettlementData memory settlementData
    ) internal returns (PerpTradeResult memory perpTradeResult, IPredyPool.TradeResult memory tradeResult) {
        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(pairId, vaultId, tradeAmount, 0, abi.encode(marginAmount)), settlementData
        );

        vaultId = tradeResult.vaultId;

        perpTradeResult = performTradePostProcessing(positionId, tradeAmount, tradeResult);
    }

    function performTradePostProcessing(
        uint256 positionId,
        int256 tradeAmount,
        IPredyPool.TradeResult memory tradeResult
    ) internal returns (PerpTradeResult memory perpTradeResult) {
        UserPosition storage userPosition = userPositions[positionId];

        perpTradeResult.tradeAmount = tradeAmount;

        (perpTradeResult.entryUpdate, perpTradeResult.payoff) = Perp.calculateEntry(
            userPosition.positionAmount,
            userPosition.entryValue,
            tradeAmount,
            tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff
        );

        userPosition.entryValue += perpTradeResult.entryUpdate;

        updateLongShort(userPosition.positionAmount, tradeAmount);

        userPosition.positionAmount += tradeAmount;
        userPosition.marginAmount += perpTradeResult.payoff;

        //
        userPosition.cumulativeFundingRates = fundingRateGrobalGrowth;
    }

    function updateLongShort(int256 positionAmount, int256 tradeAmount) internal {
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
            totalPosition.totalLongAmount += uint256(openAmount);
        }
        if (openAmount < 0) {
            totalPosition.totalShortAmount += uint256(-openAmount);
        }
        if (closeAmount > 0) {
            totalPosition.totalShortAmount -= uint256(closeAmount);
        }
        if (closeAmount < 0) {
            totalPosition.totalLongAmount -= uint256(-closeAmount);
        }
    }

    function calculatePositionValue(UserPosition memory userPosition, uint256 sqrtPrice) internal pure returns (bool) {
        int256 price = int256((sqrtPrice * sqrtPrice) >> Constants.RESOLUTION);

        int256 value = userPosition.marginAmount + userPosition.positionAmount * price / int256(Constants.Q96)
            - userPosition.entryValue;
        int256 min = userPosition.positionAmount * price / int256(Constants.Q96 * 50);

        return value >= min;
    }

    function checkFillerMinDeposit() internal view {
        DataType.Vault memory vault = _predyPool.getVault(vaultId);

        uint256 minDeposit = getFillerMinDeposit(_predyPool.getSqrtIndexPrice(vault.openPosition.pairId));

        require(vault.margin >= int256(minDeposit), "MIN");
    }

    function getFillerMinDeposit(uint256 sqrtPrice) internal view returns (uint256) {
        uint256 price = uint256(sqrtPrice * sqrtPrice) >> Constants.RESOLUTION;

        uint256 longSideMinDeposit = totalPosition.totalLongAmount * price / (Constants.Q96 * 5);
        uint256 shortSideMinDeposit = totalPosition.totalShortAmount * price / (Constants.Q96 * 5);

        if (longSideMinDeposit > shortSideMinDeposit) {
            return longSideMinDeposit;
        } else {
            return shortSideMinDeposit;
        }
    }
}
