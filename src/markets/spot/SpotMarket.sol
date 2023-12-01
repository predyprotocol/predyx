// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISettlement} from "../../interfaces/ISettlement.sol";
import {IFillerMarket} from "../../interfaces/IFillerMarket.sol";
import {ILendingPool} from "../../interfaces/ILendingPool.sol";
import {ISpotOrderValidator} from "../../interfaces/IOrderValidator.sol";
import {Permit2Lib} from "../../libraries/orders/Permit2Lib.sol";
import {ResolvedOrderLib, ResolvedOrder} from "../../libraries/orders/ResolvedOrder.sol";
import {SpotOrderLib, SpotOrder} from "./SpotOrder.sol";

/**
 * @notice Spot market contract
 * A trader can swap tokens.
 */
contract SpotMarket is IFillerMarket, ILendingPool {
    using ResolvedOrderLib for ResolvedOrder;
    using SpotOrderLib for SpotOrder;
    using Permit2Lib for ResolvedOrder;

    error LockedBy(address);

    error RequiredQuoteAmountExceedsMax();

    error BaseCurrencyNotSettled();

    struct LockData {
        address locker;
        address quoteToken;
        address baseToken;
    }

    event SpotTraded(
        address trader,
        address filler,
        address baseToken,
        address quoteToken,
        int256 baseAmount,
        int256 quoteAmount,
        address validatorAddress
    );

    IPermit2 private immutable _permit2;

    LockData private lockData;

    modifier onlyByLocker() {
        address locker = lockData.locker;

        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    constructor(address permit2Address) {
        _permit2 = IPermit2(permit2Address);
    }

    /**
     * @notice Verifies signature of the order and open new predict position
     * @param order The order signed by trader
     * @param settlementData The route of settlement created by filler
     */
    function executeOrder(SignedOrder memory order, ISettlement.SettlementData memory settlementData)
        external
        returns (int256 quoteTokenAmount)
    {
        SpotOrder memory spotOrder = abi.decode(order.order, (SpotOrder));
        ResolvedOrder memory resolvedOrder = SpotOrderLib.resolve(spotOrder, order.sig);

        _verifyOrder(resolvedOrder);

        int256 baseTokenAmount = spotOrder.baseTokenAmount;

        quoteTokenAmount = _swap(spotOrder, settlementData, baseTokenAmount);

        ISpotOrderValidator(spotOrder.validatorAddress).validate(
            spotOrder, baseTokenAmount, quoteTokenAmount, msg.sender
        );

        if (quoteTokenAmount > 0) {
            TransferHelper.safeTransfer(spotOrder.quoteToken, spotOrder.info.trader, uint256(quoteTokenAmount));
        } else if (quoteTokenAmount < 0) {
            int256 diff = int256(spotOrder.quoteTokenAmount) + quoteTokenAmount;

            if (diff < 0) {
                revert RequiredQuoteAmountExceedsMax();
            }

            if (diff > 0) {
                TransferHelper.safeTransfer(spotOrder.quoteToken, spotOrder.info.trader, uint256(diff));
            }
        }

        if (baseTokenAmount > 0) {
            TransferHelper.safeTransfer(spotOrder.baseToken, spotOrder.info.trader, uint256(baseTokenAmount));
        }

        emit SpotTraded(
            spotOrder.info.trader,
            msg.sender,
            spotOrder.baseToken,
            spotOrder.quoteToken,
            baseTokenAmount,
            quoteTokenAmount,
            spotOrder.validatorAddress
        );
    }

    /**
     * @notice Takes tokens
     * @dev Only locker can call this function
     */
    function take(bool isQuoteAsset, address to, uint256 amount) external onlyByLocker {
        if (isQuoteAsset) {
            TransferHelper.safeTransfer(lockData.quoteToken, to, amount);
        } else {
            TransferHelper.safeTransfer(lockData.baseToken, to, amount);
        }
    }

    function _swap(SpotOrder memory spotOrder, ISettlement.SettlementData memory settlementData, int256 totalBaseAmount)
        internal
        returns (int256)
    {
        uint256 quoteReserve = IERC20(spotOrder.quoteToken).balanceOf(address(this));
        uint256 baseReserve = IERC20(spotOrder.baseToken).balanceOf(address(this));

        lockData.locker = settlementData.settlementContractAddress;
        lockData.quoteToken = spotOrder.quoteToken;
        lockData.baseToken = spotOrder.baseToken;

        ISettlement(settlementData.settlementContractAddress).predySettlementCallback(
            settlementData.encodedData, -totalBaseAmount
        );

        uint256 afterQuoteReserve = IERC20(spotOrder.quoteToken).balanceOf(address(this));
        uint256 afterBaseReserve = IERC20(spotOrder.baseToken).balanceOf(address(this));

        if (totalBaseAmount + int256(baseReserve) != int256(afterBaseReserve)) {
            revert BaseCurrencyNotSettled();
        }

        return int256(afterQuoteReserve) - int256(quoteReserve);
    }

    function _verifyOrder(ResolvedOrder memory order) internal {
        order.validate();

        _permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(address(this)),
            order.info.trader,
            order.hash,
            SpotOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }
}
