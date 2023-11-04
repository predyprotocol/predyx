// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool as IAavePool} from "../../lib/aave-v3-core/contracts/interfaces/IPool.sol";
import {IFillerMarket} from "../interfaces/IFillerMarket.sol";
import {ISettlement} from "../interfaces/ISettlement.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {Math} from "../libraries/math/Math.sol";
import {Perp} from "../libraries/Perp.sol";
import {ArrayLib} from "../libraries/ArrayLib.sol";
import {Permit2Lib} from "../libraries/orders/Permit2Lib.sol";
import {ResolvedOrderLib, ResolvedOrder} from "../libraries/orders/ResolvedOrder.sol";
import {PerpOrderLib, PerpOrder} from "../libraries/orders/PerpOrder.sol";

contract AavePerp is IFillerMarket, ILendingPool {
    using ResolvedOrderLib for ResolvedOrder;
    using PerpOrderLib for PerpOrder;
    using Permit2Lib for ResolvedOrder;
    using Math for int256;
    using ArrayLib for uint256;
    using ArrayLib for address;

    IPermit2 _permit2;

    IAavePool _aavePool;

    error LockedBy(address);
    error CurrencyNotSettled();

    struct PerpTradeResult {
        int256 entryUpdate;
        int256 payoff;
    }

    struct InsurancePool {
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
        int256 globalBaseAmount;
        int256 globalQuoteAmount;
    }

    struct Pair {
        address quoteToken;
        address baseToken;
    }

    struct LockData {
        address locker;
        uint256 quoteReserve;
        uint256 baseReserve;
        uint256 pairId;
    }

    struct UserPosition {
        uint256 id;
        uint256 pairId;
        address filler;
        address owner;
        int256 positionAmount;
        int256 entryValue;
        int256 marginAmount;
        int256 cumulativeFundingRates;
    }

    struct FlashLoanCallbackParams {
        PerpOrder order;
        ISettlement.SettlementData settlementData;
        address caller;
    }

    struct FlashLoanParams {
        uint256 amount;
    }

    mapping(uint256 => InsurancePool) public insurancePools;

    mapping(uint256 => Pair) public pairs;

    mapping(uint256 => UserPosition) public userPositions;

    uint256 public pairCount;

    uint256 public positionCount;

    LockData internal _lockData;

    PerpTradeResult internal _tmpResult;

    modifier onlyFiller(uint256 fillerPoolId) {
        if (insurancePools[fillerPoolId].fillerAddress != msg.sender) revert CallerIsNotFiller();
        _;
    }

    constructor(address permit2Address, address aavePool) {
        _permit2 = IPermit2(permit2Address);
        _aavePool = IAavePool(aavePool);

        pairCount = 1;
        positionCount = 1;
    }

    function addPair(address quoteToken, address baseToken) external returns (uint256 pairId) {
        pairId = pairCount;

        pairs[pairId] = Pair(quoteToken, baseToken);
        insurancePools[pairId].fillerAddress = msg.sender;

        pairCount++;
    }

    /**
     * @notice Deposits margin to the insurance pool.
     * @param pairId The id of filler pool
     * @param depositAmount The amount to deposit
     */
    function depositToInsurancePool(uint256 pairId, uint256 depositAmount) external onlyFiller(pairId) {
        require(depositAmount > 0);

        address quoteTokenAddress = pairs[pairId].quoteToken;

        IERC20(quoteTokenAddress).transferFrom(msg.sender, address(this), depositAmount);

        insurancePools[pairId].marginAmount += int256(depositAmount);

        IERC20(quoteTokenAddress).approve(address(_aavePool), depositAmount);

        _aavePool.supply(quoteTokenAddress, depositAmount, address(this), 0);
    }

    /**
     * @notice Verifies signature of the order and executes trade
     * @dev Fillers can open position and anyone can close position
     * @param order The order signed by trader
     * @param settlementData The route of settlement created by filler
     * @param flashLoanParams Parameters for flashloan
     */
    function executeOrder(
        SignedOrder memory order,
        ISettlement.SettlementData memory settlementData,
        FlashLoanParams memory flashLoanParams
    ) external returns (PerpTradeResult memory result) {
        PerpOrder memory perpOrder = abi.decode(order.order, (PerpOrder));
        ResolvedOrder memory resolvedOrder = PerpOrderLib.resolve(perpOrder, order.sig);

        _verifyOrder(resolvedOrder);

        address currency;

        if (perpOrder.tradeAmount > 0) {
            currency = pairs[perpOrder.pairId].quoteToken;
        } else {
            currency = pairs[perpOrder.pairId].baseToken;
        }

        _aavePool.flashLoan({
            receiverAddress: address(this),
            assets: currency.toArray(),
            amounts: flashLoanParams.amount.toArray(),
            interestRateModes: uint256(2).toArray(),
            onBehalfOf: address(this),
            params: abi.encode(
                FlashLoanCallbackParams({caller: msg.sender, order: perpOrder, settlementData: settlementData})
                ),
            referralCode: 0
        });

        result = _tmpResult;

        delete _tmpResult;
    }

    function executeOperation(
        address[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == address(_aavePool) && initiator == address(this));

        FlashLoanCallbackParams memory callbackParams = abi.decode(params, (FlashLoanCallbackParams));

        _tmpResult = _executeOrder(callbackParams.order, callbackParams.settlementData, callbackParams.caller);

        return true;
    }

    /**
     * @notice Executes liquidation call for the position
     * @dev Anyone can liquidate position but only filler can cover negative margin
     * @param positionId The id of position
     * @param settlementData The route of settlement created by liquidator
     */
    function execLiquidationCall(uint256 positionId, ISettlement.SettlementData memory settlementData) external {

    }

    function _executeOrder(PerpOrder memory perpOrder, ISettlement.SettlementData memory settlementData, address caller)
        internal
        returns (PerpTradeResult memory perpTradeResult)
    {
        if (perpOrder.positionId == 0) {
            perpOrder.positionId = positionCount;

            userPositions[perpOrder.positionId].id = perpOrder.positionId;
            userPositions[perpOrder.positionId].owner = perpOrder.info.trader;
            userPositions[perpOrder.positionId].pairId = perpOrder.pairId;
            userPositions[perpOrder.positionId].filler = perpOrder.info.filler;

            positionCount++;
        }

        _initializeLock(perpOrder.pairId, settlementData.settlementContractAddress);

        ISettlement(settlementData.settlementContractAddress).predySettlementCallback(
            settlementData.encodedData, -perpOrder.tradeAmount
        );

        int256 totalQuoteAmount = _settle(true);

        if (_settle(false) != perpOrder.tradeAmount) {
            revert CurrencyNotSettled();
        }

        delete _lockData;

        return _performTradePostProcessing(
            insurancePools[perpOrder.pairId], perpOrder.positionId, perpOrder.tradeAmount, totalQuoteAmount, caller
        );
    }

    /**
     * @notice Takes tokens
     * @dev Only locker can call this function
     */
    function take(bool isQuoteAsset, address to, uint256 amount) external {
        address currency;

        if (isQuoteAsset) {
            currency = pairs[_lockData.pairId].quoteToken;
        } else {
            currency = pairs[_lockData.pairId].baseToken;
        }

        IERC20(currency).transfer(to, amount);
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

    function _initializeLock(uint256 pairId, address caller) internal {
        if (_lockData.locker != address(0)) {
            revert LockedBy(_lockData.locker);
        }

        _lockData.quoteReserve = IERC20(pairs[pairId].quoteToken).balanceOf(address(this));
        _lockData.baseReserve = IERC20(pairs[pairId].baseToken).balanceOf(address(this));
        _lockData.locker = caller;
        _lockData.pairId = pairId;
    }

    function _settle(bool isQuoteAsset) internal returns (int256 paid) {
        address currency;
        uint256 reservesBefore;

        if (isQuoteAsset) {
            currency = pairs[_lockData.pairId].quoteToken;
            reservesBefore = _lockData.quoteReserve;
        } else {
            currency = pairs[_lockData.pairId].baseToken;
            reservesBefore = _lockData.baseReserve;
        }

        uint256 reserveAfter = IERC20(currency).balanceOf(address(this));

        if (isQuoteAsset) {
            _lockData.quoteReserve = reserveAfter;
        } else {
            _lockData.baseReserve = reserveAfter;
        }

        paid = int256(reserveAfter) - int256(reservesBefore);
    }

    function _performTradePostProcessing(
        InsurancePool storage insurancePool,
        uint256 positionId,
        int256 tradeAmount,
        int256 quoteAmount,
        address caller
    ) internal returns (PerpTradeResult memory perpTradeResult) {
        UserPosition storage userPosition = userPositions[positionId];

        (perpTradeResult.entryUpdate, perpTradeResult.payoff) =
            Perp.calculateEntry(userPosition.positionAmount, userPosition.entryValue, tradeAmount, quoteAmount);

        userPosition.entryValue += perpTradeResult.entryUpdate;

        updateLongShort(insurancePool, userPosition.positionAmount, tradeAmount, caller);

        userPosition.positionAmount += tradeAmount;
        userPosition.marginAmount += perpTradeResult.payoff;

        //
        userPosition.cumulativeFundingRates = insurancePool.fundingRateGrobalGrowth;

        address baseTokenAddress = pairs[userPosition.pairId].baseToken;
        address quoteTokenAddress = pairs[userPosition.pairId].quoteToken;

        _updateAavePosition(baseTokenAddress, insurancePool.totalPosition.globalBaseAmount, tradeAmount);

        _updateAavePosition(
            quoteTokenAddress, insurancePool.totalPosition.globalQuoteAmount, perpTradeResult.entryUpdate
        );

        insurancePool.totalPosition.globalBaseAmount += tradeAmount;
        insurancePool.totalPosition.globalQuoteAmount += perpTradeResult.entryUpdate;
    }

    function _updateAavePosition(address asset, int256 positionAmount, int256 tradeAmount) internal {
        (int256 openAmount, int256 closeAmount) = _calculateOpenAndCloseAmount(positionAmount, tradeAmount);

        if (openAmount > 0) {
            IERC20(asset).approve(address(_aavePool), uint256(openAmount));
            _aavePool.supply(asset, uint256(openAmount), address(this), 0);
        } else if (openAmount < 0) {
            _aavePool.borrow(asset, uint256(-openAmount), 2, 0, address(this));
        }

        if (closeAmount > 0) {
            _aavePool.repay(asset, uint256(closeAmount), 2, address(this));
        } else if (closeAmount < 0) {
            _aavePool.withdraw(asset, uint256(-closeAmount), address(this));
        }
    }

    function _calculateOpenAndCloseAmount(int256 positionAmount, int256 tradeAmount)
        internal
        pure
        returns (int256 openAmount, int256 closeAmount)
    {
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
    }

    function updateLongShort(
        InsurancePool storage insurancePool,
        int256 positionAmount,
        int256 tradeAmount,
        address caller
    ) internal {
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
            insurancePool.totalPosition.totalLongAmount += uint256(openAmount);
        }
        if (openAmount < 0) {
            insurancePool.totalPosition.totalShortAmount += uint256(-openAmount);
        }
        if (closeAmount > 0) {
            insurancePool.totalPosition.totalShortAmount -= uint256(closeAmount);
        }
        if (closeAmount < 0) {
            insurancePool.totalPosition.totalLongAmount -= uint256(-closeAmount);
        }

        // only filler can open position
        if (openAmount != 0 && insurancePool.fillerAddress != caller) {
            revert CallerIsNotFiller();
        }
    }
}
