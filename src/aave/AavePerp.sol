// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool as IAavePool} from "../../lib/aave-v3-core/contracts/interfaces/IPool.sol";
import "../interfaces/IFillerMarket.sol";
import "../interfaces/ISettlement.sol";
import "../interfaces/ILendingPool.sol";
import {Permit2Lib} from "../libraries/orders/Permit2Lib.sol";
import {ResolvedOrderLib, ResolvedOrder} from "../libraries/orders/ResolvedOrder.sol";
import {PerpOrderLib, PerpOrder} from "../libraries/orders/PerpOrder.sol";

contract AavePerp is IFillerMarket, ILendingPool {
    using ResolvedOrderLib for ResolvedOrder;
    using PerpOrderLib for PerpOrder;
    using Permit2Lib for ResolvedOrder;

    IPermit2 _permit2;

    IAavePool _aavePool;

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
    }

    struct Pair {
        address quoteToken;
        address baseToken;
    }

    mapping(uint256 => InsurancePool) public insurancePools;

    mapping(uint256 => Pair) public pairs;

    uint256 public pairCount;

    modifier onlyFiller(uint256 fillerPoolId) {
        if (insurancePools[fillerPoolId].fillerAddress != msg.sender) revert CallerIsNotFiller();
        _;
    }

    constructor(address permit2Address, address aavePool) {
        _permit2 = IPermit2(permit2Address);
        _aavePool = IAavePool(aavePool);

        pairCount = 1;
    }

    function addPair(address quoteToken, address baseToken) external returns(uint256 pairId) {
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

        _aavePool.supply(
            quoteTokenAddress,
            depositAmount,
            address(this),
            0
        );
    }
    
    function executeOrder(SignedOrder memory order, ISettlement.SettlementData memory settlementData)
        external
        returns (PerpTradeResult memory perpTradeResult)
    {
        PerpOrder memory perpOrder = abi.decode(order.order, (PerpOrder));
        ResolvedOrder memory resolvedOrder = PerpOrderLib.resolve(perpOrder, order.sig);

        _verifyOrder(resolvedOrder);
    }

    /**
     * @notice Takes tokens
     * @dev Only locker can call this function
     */
    function take(bool isQuoteAsset, address to, uint256 amount) external {}


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
}
