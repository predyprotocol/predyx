// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPredyPool.sol";
import "./interfaces/IFillerMarket.sol";
import "./base/BaseMarket.sol";
import "./libraries/market/Permit2Lib.sol";
import "./libraries/market/ResolvedOrder.sol";
import "./libraries/market/GeneralOrderLib.sol";
import "./libraries/math/Math.sol";
import "./libraries/Perp.sol";
import "./libraries/Constants.sol";

/**
 * @notice Provides perps to retail traders
 */
contract PerpMarket is IFillerMarket, BaseMarket {
    using ResolvedOrderLib for ResolvedOrder;
    using GeneralOrderLib for GeneralOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for uint256;

    IPermit2 _permit2;
    address _quoteTokenAddress;
    address _fillerAddress;

    struct UserPosition {
        uint64 pairId;
        address owner;
        int256 positionAmount;
        int256 entryValue;
        int256 marginAmount;
        int256 marginCoveredByFiller;
    }

    error CallerIsNotFiller();

    mapping(uint256 vaultId => UserPosition) public userPositions;

    uint64 positionCounts;
    uint256 vaultId;

    constructor(
        IPredyPool _predyPool,
        address swapRouterAddress,
        address quoteTokenAddress,
        address permit2Address,
        address fillerAddress
    ) BaseMarket(_predyPool, swapRouterAddress) {
        _quoteTokenAddress = quoteTokenAddress;
        _permit2 = IPermit2(permit2Address);
        _fillerAddress = fillerAddress;
        positionCounts = 1;
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseMarket) {}

    function predyLiquidationCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult,
        int256 marginAmount
    ) external override(BaseMarket) {
        UserPosition memory userPosition = userPositions[tradeParams.vaultId];

        if (tradeResult.minDeposit == 0 && marginAmount > 0) {
            _predyPool.take(true, address(this), uint256(marginAmount));

            IERC20(_quoteTokenAddress).transfer(
                userPosition.owner, uint256(marginAmount - userPosition.marginCoveredByFiller)
            );
        }
    }

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
            if (generalOrder.info.trader != userPositions[generalOrder.positionId].owner) {
                revert IFillerMarket.SignerIsNotVaultOwner();
            }
        }

        tradeResult = coverPosition(
            generalOrder.pairId,
            generalOrder.positionId,
            generalOrder.tradeAmount,
            generalOrder.marginAmount,
            settlementData
        );

        {
            if (userPositions[generalOrder.positionId].positionAmount != 0 && msg.sender != _fillerAddress) {
                revert CallerIsNotFiller();
            }
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
            IERC20(_quoteTokenAddress).transfer(generalOrder.info.trader, uint256(-generalOrder.marginAmount));
        }

        return tradeResult;
    }

    /**
     * @notice Executes liquidation call for the position
     * @param positionId The id of position
     * @param settlementData The route of settlement created by liquidator
     */
    function execLiquidationCall(uint256 positionId, bytes memory settlementData) external {
        UserPosition memory userPosition = userPositions[positionId];

        // TODO: liquidation call
        // check vault is danger
        require(!calculatePositionValue(userPosition, _predyPool.getSqrtIndexPrice(userPosition.pairId)), "NOT SAFE");

        coverPosition(userPosition.pairId, positionId, -userPosition.positionAmount, 0, settlementData);
    }

    function depositToFillerPool(uint256 depositAmount) external {
        IERC20(_quoteTokenAddress).transferFrom(msg.sender, address(this), depositAmount);

        _predyPool.updateMargin(vaultId, int256(depositAmount));
    }

    function withdrawFromFillerPool(uint256 withdrawAmount) external {
        _predyPool.updateMargin(vaultId, -int256(withdrawAmount));

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

    function coverPosition(
        uint64 pairId,
        uint256 positionId,
        int256 tradeAmount,
        int256 marginAmount,
        bytes memory settlementData
    ) internal returns (IPredyPool.TradeResult memory tradeResult) {
        tradeResult = _predyPool.trade(
            IPredyPool.TradeParams(pairId, vaultId, tradeAmount, 0, abi.encode(marginAmount)), settlementData
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

        userPosition.positionAmount += tradeAmount;
        userPosition.marginAmount += payoff;
    }

    function calculatePositionValue(UserPosition memory userPosition, uint160 sqrtPrice) internal view returns (bool) {
        int256 price = int256(uint256(sqrtPrice * sqrtPrice) >> Constants.RESOLUTION);

        int256 value = userPosition.marginAmount + userPosition.positionAmount * price / int256(Constants.Q96)
            - userPosition.entryValue;
        int256 min = userPosition.positionAmount * price / int256(Constants.Q96 * 50);

        return value >= min;
    }
}
