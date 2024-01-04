// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {ISettlement} from "../../interfaces/ISettlement.sol";
import {IFillerMarket} from "../../interfaces/IFillerMarket.sol";
import {ISpotOrderValidator} from "../../interfaces/IOrderValidator.sol";
import {Permit2Lib} from "../../libraries/orders/Permit2Lib.sol";
import {Constants} from "../../libraries/Constants.sol";
import {Math} from "../../libraries/math/Math.sol";
import {ResolvedOrderLib, ResolvedOrder} from "../../libraries/orders/ResolvedOrder.sol";
import {SpotOrderLib, SpotOrder} from "./SpotOrder.sol";

/**
 * @notice Spot market contract
 * A trader can swap tokens.
 */
contract SpotMarket is IFillerMarket {
    using ResolvedOrderLib for ResolvedOrder;
    using SpotOrderLib for SpotOrder;
    using Permit2Lib for ResolvedOrder;
    using SafeTransferLib for ERC20;
    using Math for uint256;

    error RequiredQuoteAmountExceedsMax();

    error BaseCurrencyNotSettled();

    struct LockData {
        address quoteToken;
        address baseToken;
    }

    event SpotTraded(
        address indexed trader,
        address filler,
        address baseToken,
        address quoteToken,
        int256 baseAmount,
        int256 quoteAmount,
        address validatorAddress
    );

    IPermit2 private immutable _permit2;

    LockData private lockData;

    constructor(address permit2Address) {
        _permit2 = IPermit2(permit2Address);
    }

    /**
     * @notice Verifies signature of the order and open new predict position
     * @param order The order signed by trader
     * @param settlementParams The route of settlement created by filler
     */
    function executeOrder(SignedOrder memory order, SettlementParams memory settlementParams)
        external
        returns (int256 quoteTokenAmount)
    {
        SpotOrder memory spotOrder = abi.decode(order.order, (SpotOrder));
        ResolvedOrder memory resolvedOrder = SpotOrderLib.resolve(spotOrder, order.sig);

        _verifyOrder(resolvedOrder);

        int256 baseTokenAmount = spotOrder.baseTokenAmount;

        quoteTokenAmount = _swap(spotOrder, settlementParams, baseTokenAmount);

        ISpotOrderValidator(spotOrder.validatorAddress).validate(spotOrder, quoteTokenAmount, msg.sender);

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

    function _swap(SpotOrder memory spotOrder, SettlementParams memory settlementParams, int256 totalBaseAmount)
        internal
        returns (int256)
    {
        uint256 quoteReserve = ERC20(spotOrder.quoteToken).balanceOf(address(this));
        uint256 baseReserve = ERC20(spotOrder.baseToken).balanceOf(address(this));

        lockData.quoteToken = spotOrder.quoteToken;
        lockData.baseToken = spotOrder.baseToken;

        _execSettlement(spotOrder.quoteToken, spotOrder.baseToken, settlementParams, -totalBaseAmount);

        uint256 afterQuoteReserve = ERC20(spotOrder.quoteToken).balanceOf(address(this));
        uint256 afterBaseReserve = ERC20(spotOrder.baseToken).balanceOf(address(this));

        if (totalBaseAmount + int256(baseReserve) != int256(afterBaseReserve)) {
            revert BaseCurrencyNotSettled();
        }

        return int256(afterQuoteReserve) - int256(quoteReserve);
    }

    function _execSettlement(
        address quoteToken,
        address baseToken,
        SettlementParams memory settlementParams,
        int256 baseAmountDelta
    ) internal {
        if (baseAmountDelta > 0) {
            _execSell(quoteToken, baseToken, settlementParams, uint256(baseAmountDelta));
        } else if (baseAmountDelta < 0) {
            _execBuy(quoteToken, baseToken, settlementParams, uint256(-baseAmountDelta));
        }
    }

    function _execSell(
        address quoteToken,
        address baseToken,
        SettlementParams memory settlementParams,
        uint256 sellAmount
    ) internal {
        if (settlementParams.contractAddress == address(0)) {
            uint256 quoteAmount = sellAmount * settlementParams.price / Constants.Q96;

            ERC20(baseToken).safeTransfer(msg.sender, sellAmount);

            ERC20(quoteToken).safeTransferFrom(msg.sender, address(this), quoteAmount);

            return;
        }

        ERC20(baseToken).safeTransfer(settlementParams.contractAddress, sellAmount);

        uint256 quoteAmountFromUni = ISettlement(settlementParams.contractAddress).swapExactIn(
            quoteToken,
            baseToken,
            settlementParams.encodedData,
            sellAmount,
            settlementParams.maxQuoteAmount,
            address(this)
        );

        if (settlementParams.price == 0) {
            ERC20(quoteToken).safeTransfer(msg.sender, uint256(settlementParams.fee));
        } else {
            uint256 quoteAmount = sellAmount * settlementParams.price / Constants.Q96;

            if (quoteAmount > quoteAmountFromUni) {
                ERC20(quoteToken).safeTransferFrom(msg.sender, address(this), quoteAmount - quoteAmountFromUni);
            } else if (quoteAmountFromUni > quoteAmount) {
                ERC20(quoteToken).safeTransfer(msg.sender, quoteAmountFromUni - quoteAmount);
            }
        }
    }

    function _execBuy(
        address quoteToken,
        address baseToken,
        SettlementParams memory settlementParams,
        uint256 buyAmount
    ) internal {
        if (settlementParams.contractAddress == address(0)) {
            uint256 quoteAmount = buyAmount * settlementParams.price / Constants.Q96;

            ERC20(quoteToken).safeTransfer(msg.sender, quoteAmount);

            ERC20(baseToken).safeTransferFrom(msg.sender, address(this), buyAmount);

            return;
        }

        ERC20(quoteToken).safeTransfer(settlementParams.contractAddress, settlementParams.maxQuoteAmount);

        uint256 quoteAmountToUni = ISettlement(settlementParams.contractAddress).swapExactOut(
            quoteToken,
            baseToken,
            settlementParams.encodedData,
            buyAmount,
            settlementParams.maxQuoteAmount,
            address(this)
        );

        if (settlementParams.price == 0) {
            ERC20(quoteToken).safeTransfer(msg.sender, uint256(settlementParams.fee));
        } else {
            uint256 quoteAmount = buyAmount * settlementParams.price / Constants.Q96;

            if (quoteAmount > quoteAmountToUni) {
                ERC20(quoteToken).safeTransfer(msg.sender, quoteAmount - quoteAmountToUni);
            } else if (quoteAmountToUni > quoteAmount) {
                ERC20(quoteToken).safeTransferFrom(msg.sender, address(this), quoteAmountToUni - quoteAmount);
            }
        }
    }

    function quoteSettlement(SettlementParams memory settlementParams, int256 baseAmountDelta) external {
        _revertQuoteAmount(_quoteSettlement(settlementParams, baseAmountDelta));
    }

    function _quoteSettlement(SettlementParams memory settlementParams, int256 baseAmountDelta)
        internal
        returns (int256)
    {
        if (baseAmountDelta > 0) {
            return _quoteSell(settlementParams, uint256(baseAmountDelta));
        } else if (baseAmountDelta < 0) {
            return _quoteBuy(settlementParams, uint256(-baseAmountDelta));
        } else {
            return 0;
        }
    }

    function _quoteSell(SettlementParams memory settlementParams, uint256 sellAmount) internal returns (int256) {
        if (settlementParams.contractAddress == address(0)) {
            uint256 quoteAmount = sellAmount * settlementParams.price / Constants.Q96;

            return int256(quoteAmount);
        }

        uint256 quoteAmountFromUni =
            ISettlement(settlementParams.contractAddress).quoteSwapExactIn(settlementParams.encodedData, sellAmount);

        if (settlementParams.price == 0) {
            return int256(quoteAmountFromUni.addDelta(-settlementParams.fee));
        } else {
            uint256 quoteAmount = sellAmount * settlementParams.price / Constants.Q96;

            return int256(quoteAmount);
        }
    }

    function _quoteBuy(SettlementParams memory settlementParams, uint256 buyAmount) internal returns (int256) {
        if (settlementParams.contractAddress == address(0)) {
            uint256 quoteAmount = buyAmount * settlementParams.price / Constants.Q96;

            return -int256(quoteAmount);
        }

        uint256 quoteAmountToUni =
            ISettlement(settlementParams.contractAddress).quoteSwapExactOut(settlementParams.encodedData, buyAmount);

        if (settlementParams.price == 0) {
            return -int256(quoteAmountToUni.addDelta(settlementParams.fee));
        } else {
            uint256 quoteAmount = buyAmount * settlementParams.price / Constants.Q96;

            return -int256(quoteAmount);
        }
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

    function _revertQuoteAmount(int256 quoteAmount) internal pure {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, quoteAmount)
            revert(ptr, 32)
        }
    }
}
