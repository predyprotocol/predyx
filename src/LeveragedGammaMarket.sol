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

/**
 * @notice Provides leveraged perps to retail traders
 */
contract LeveragedGammaMarket is IFillerMarket, BaseHookCallback {
    using ResolvedOrderLib for ResolvedOrder;
    using GeneralOrderLib for GeneralOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;
    using Math for int256;

    IPermit2 _permit2;
    address _quoteTokenAddress;

    struct Filler {
        uint256 pairId;
        address fillerAddress;
        int256 marginAmount;
        int256 fillercumulativeFundingRates;
        int256 fundingRateGrobalGrowth;
        uint256 lastFundingRateCalculationTime;
    }

    struct UserPosition {
        address filler;
        address owner;
        int256 positionAmount;
        int256 assuranceMargin;
        int256 marginAmount;
        bool isLiquidated;
        int256 liquidatedPrice;
    }

    error CallerIsNotFiller();

    mapping(uint256 vaultId => UserPosition) public userPositions;

    mapping(address => Filler) public fillers;

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
        int256 margin = _predyPool.getVault(tradeParams.vaultId).margin;
        int256 currentAssuranceMargin = userPositions[tradeParams.vaultId].assuranceMargin;

        int256 marginAmountUpdate = abi.decode(tradeParams.extraData, (int256));
        int256 fillerMinDeposit = 9 * tradeResult.minMargin / 10;

        int256 userMargin = margin - currentAssuranceMargin;

        require(userMargin + marginAmountUpdate >= 0);

        userPositions[tradeParams.vaultId].assuranceMargin = fillerMinDeposit;

        int256 diff = userMargin + marginAmountUpdate + fillerMinDeposit - currentAssuranceMargin;

        if (diff > 0) {
            IERC20(_quoteTokenAddress).transfer(address(_predyPool), uint256(diff));
        } else if (diff < 0) {
            _predyPool.take(true, address(this), uint256(-diff));
        }
    }

    /*
    function depositToFillerPool(uint256 fillerPoolId, uint256 depositAmount) external {
        IERC20(_quoteTokenAddress).transferFrom(msg.sender, address(this), depositAmount);

        fillers[fillerPoolId].marginAmount += int256(depositAmount);

        IERC20(_quoteTokenAddress).approve(address(_predyPool), depositAmount);
        _predyPool.updateMargin(fillers[fillerPoolId].vaultId, int256(depositAmount));
    }

    function withdrawFromFillerPool(uint256 fillerPoolId, uint256 withdrawAmount)
        external
        onlyWhitelisted(fillerPoolId)
    {
        _predyPool.updateMargin(fillers[fillerPoolId].vaultId, -int256(withdrawAmount));

        fillers[fillerPoolId].marginAmount -= int256(withdrawAmount);

        checkFillerMinDeposit(fillerPoolId);

        IERC20(_quoteTokenAddress).transfer(msg.sender, withdrawAmount);
    }
    */

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
        (GeneralOrder memory generalOrder, ResolvedOrder memory resolvedOrder) =
            GeneralOrderLib.resolve(order, _quoteTokenAddress);

        _verifyOrder(resolvedOrder);

        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(
                generalOrder.pairId,
                generalOrder.positionId,
                generalOrder.tradeAmount,
                generalOrder.tradeAmountSqrt,
                abi.encode(generalOrder.marginAmount)
            ),
            settlementData
        );

        if (generalOrder.positionId == 0) {
            userPositions[tradeResult.vaultId].owner = generalOrder.info.trader;

            _predyPool.updateRecepient(tradeResult.vaultId, generalOrder.info.trader);
        } else {
            if (generalOrder.info.trader != userPositions[tradeResult.vaultId].owner) {
                revert IFillerMarket.SignerIsNotVaultOwner();
            }
        }

        // TODO: should have whote list for validatorAddress?
        IOrderValidator(generalOrder.validatorAddress).validate(generalOrder, tradeResult);

        if (generalOrder.marginAmount < 0) {
            IERC20(_quoteTokenAddress).transfer(generalOrder.info.trader, uint256(-generalOrder.marginAmount));
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
        Filler storage fillerPool = fillers[userPosition.filler];

        // check vault is danger
        require(!calculatePositionValue(userPosition, _predyPool.getSqrtIndexPrice(fillerPool.pairId)), "NOT SAFE");

        // TODO: close position
        // TODO: - filler margin

        sendMarginToUser(positionId);
    }

    function confirmLiquidation(uint256 vaultId) external {
        UserPosition storage userPosition = userPositions[vaultId];

        // TODO: check liquidated
        IPredyPool.VaultStatus memory vaultStatus = _predyPool.getVaultStatus(vaultId);

        // vault has positions but has no cover positions
        require(vaultStatus.minMargin == 0);
        // TODO: userPosition has positionAmounts

        DataType.Vault memory vault = _predyPool.getVault(vaultId);

        _predyPool.updateMargin(vaultId, -vault.margin);

        // TODO: clear userPosition
        Filler storage filler = fillers[userPosition.filler];

        filler.marginAmount += vault.margin;
    }

    // Private Functions

    function initFillerPool(uint256 pairId, address fillerAddress) internal returns (uint256) {
        uint256 vaultId = _predyPool.createVault(0, pairId);

        Filler storage fillerPool = fillers[fillerAddress];

        fillerPool.pairId = pairId;
        fillerPool.fillerAddress = fillerAddress;
        fillerPool.lastFundingRateCalculationTime = block.timestamp;

        return vaultId;
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
                fillers[userPosition.filler].marginAmount += userPosition.marginAmount;

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
            GeneralOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    function calculatePositionValue(UserPosition memory userPosition, uint256 sqrtPrice) internal pure returns (bool) {
        int256 price = int256((sqrtPrice * sqrtPrice) >> Constants.RESOLUTION);

        // TODO:
        int256 value = 0;
        int256 min = userPosition.positionAmount * price / int256(Constants.Q96 * 50);

        return value >= min;
    }
}
