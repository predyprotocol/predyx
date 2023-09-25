// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPredyPool.sol";
import "./interfaces/IFillerMarket.sol";
import "./base/BaseHookCallback.sol";
import "./libraries/market/Permit2Lib.sol";
import "./libraries/market/ResolvedOrder.sol";
import "./libraries/market/GeneralOrderLib.sol";
import "./libraries/math/Math.sol";
import "./libraries/Perp.sol";
import "./libraries/Constants.sol";
import "./libraries/DataType.sol";

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

    constructor(IPredyPool _predyPool, address quoteTokenAddress, address permit2Address, address fillerAddress)
        BaseHookCallback(_predyPool)
    {
        _quoteTokenAddress = quoteTokenAddress;
        _permit2 = IPermit2(permit2Address);
        _fillerAddress = fillerAddress;
        positionCounts = 1;
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallback) {}

    /**
     * @notice Verifies signature of the order and executes trade
     * @param order The order signed by trader
     * @param settlementData The route of settlement created by filler
     * @dev Fillers call this function
     */
    function executeOrder(SignedOrder memory order, bytes memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
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

        tradeResult = coverPosition(
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

        generalOrder.validateGeneralOrder(tradeResult);

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

        return tradeResult;
    }

    function depositMargin(uint256 marginAmount) external {}

    function withdrawMargin(uint256 marginAmount) external {}

    /**
     * @notice Executes liquidation call for the position
     * @param positionId The id of position
     * @param settlementData The route of settlement created by liquidator
     */
    function execLiquidationCall(uint64 positionId, bytes memory settlementData) external {
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
        fundingRateGrobalGrowth +=
            getFundingRate() * int256(block.timestamp - lastFundingRateCalculationTime) / int256(365 days);

        lastFundingRateCalculationTime = block.timestamp;

        int256 fundingFee =
            (fundingRateGrobalGrowth - userPosition.cumulativeFundingRates) * userPosition.positionAmount / 1e18;

        userPosition.cumulativeFundingRates = fundingRateGrobalGrowth;

        userPosition.marginAmount += fundingFee;

        // TODO: +- fee to filler margin
        fillerMarginAmount += (fillerCumulativeFundingRates - userPosition.cumulativeFundingRates)
            * (int256(totalPosition.totalLongAmount) - int256(totalPosition.totalShortAmount)) / 1e18;

        fillerCumulativeFundingRates = userPosition.cumulativeFundingRates;
    }

    function getFundingRate() internal view returns (int256) {
        // TODO: per ETH
        if (totalPosition.totalLongAmount > totalPosition.totalShortAmount) {
            return 12 * 1e16;
        } else {
            return -12 * 1e16;
        }
    }

    function coverPosition(
        uint64 pairId,
        uint256 positionId,
        int256 tradeAmount,
        int256 marginAmount,
        bytes memory settlementData
    ) internal returns (IPredyPool.TradeResult memory tradeResult) {
        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(pairId, vaultId, tradeAmount, 0, abi.encode(marginAmount)),
            ISettlement.SettlementData(address(this), settlementData)
        );

        vaultId = tradeResult.vaultId;

        performTradePostProcessing(positionId, tradeAmount, tradeResult);
    }

    function performTradePostProcessing(
        uint256 positionId,
        int256 tradeAmount,
        IPredyPool.TradeResult memory tradeResult
    ) internal returns (int256 payoff) {
        UserPosition storage userPosition = userPositions[positionId];

        (userPosition.entryValue, payoff) = Perp.calculateEntry(
            userPosition.positionAmount,
            userPosition.entryValue,
            tradeAmount,
            tradeResult.payoff.perpEntryUpdate + tradeResult.payoff.perpPayoff
        );

        updateLongShort(userPosition.positionAmount, tradeAmount);

        userPosition.positionAmount += tradeAmount;
        userPosition.marginAmount += payoff;
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

    function calculatePositionValue(UserPosition memory userPosition, uint160 sqrtPrice) internal pure returns (bool) {
        int256 price = int256(uint256(sqrtPrice * sqrtPrice) >> Constants.RESOLUTION);

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

    function getFillerMinDeposit(uint160 sqrtPrice) internal view returns (uint256) {
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
