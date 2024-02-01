// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";
import {ISettlement} from "../../interfaces/ISettlement.sol";
import {IFillerMarket} from "../../interfaces/IFillerMarket.sol";
import {ISpotMarket} from "../../interfaces/ISpotMarket.sol";
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
contract SpotMarketV1 is IFillerMarket, ISpotMarket, Owned {
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

    mapping(address settlementContractAddress => bool) internal _whiteListedSettlements;

    constructor(address permit2Address) Owned(msg.sender) {
        _permit2 = IPermit2(permit2Address);
    }

    /**
     * @notice Updates the whitelist settlement address
     * @dev only owner can call this function
     */
    function updateWhitelistSettlement(address settlementContractAddress, bool isEnabled) external onlyOwner {
        _whiteListedSettlements[settlementContractAddress] = isEnabled;
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

        return _executeOrder(spotOrder, order.sig, settlementParams);
    }

    function _executeOrder(SpotOrder memory spotOrder, bytes memory sig, SettlementParams memory settlementParams)
        internal
        returns (int256 quoteTokenAmount)
    {
        ResolvedOrder memory resolvedOrder = SpotOrderLib.resolve(spotOrder, sig);

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
        if (settlementParams.fee < 0) {
            ERC20(quoteToken).safeTransferFrom(msg.sender, address(this), uint256(-settlementParams.fee));
        }

        if (baseAmountDelta > 0) {
            _execSettlementLoop(quoteToken, baseToken, settlementParams, true, uint256(baseAmountDelta));
        } else if (baseAmountDelta < 0) {
            _execSettlementLoop(quoteToken, baseToken, settlementParams, false, uint256(-baseAmountDelta));
        }

        if (settlementParams.fee > 0) {
            ERC20(quoteToken).safeTransfer(msg.sender, uint256(settlementParams.fee));
        }
    }

    function _execSettlementLoop(
        address quoteToken,
        address baseToken,
        SettlementParams memory settlementParams,
        bool isSell,
        uint256 baseAmountDelta
    ) internal {
        uint256 remain = baseAmountDelta;

        for (uint256 i = 0; i < settlementParams.items.length; i++) {
            IFillerMarket.SettlementParamsItem memory item = settlementParams.items[i];

            if (item.contractAddress != address(0) && !_whiteListedSettlements[item.contractAddress]) {
                revert SettlementContractIsNotWhitelisted();
            }

            uint256 baseAmount = item.partialBaseAmount;

            // if the item is the last item
            if (i == settlementParams.items.length - 1) {
                baseAmount = remain;
            }

            if (isSell) {
                _execSell(quoteToken, baseToken, item, settlementParams.price, baseAmount);
            } else {
                _execBuy(quoteToken, baseToken, item, settlementParams.price, baseAmount);
            }

            remain -= baseAmount;
        }
    }

    function _execSell(
        address quoteToken,
        address baseToken,
        SettlementParamsItem memory settlementParams,
        uint256 price,
        uint256 sellAmount
    ) internal {
        if (settlementParams.contractAddress == address(0)) {
            uint256 quoteAmount = sellAmount * price / Constants.Q96;

            ERC20(baseToken).safeTransfer(msg.sender, sellAmount);

            ERC20(quoteToken).safeTransferFrom(msg.sender, address(this), quoteAmount);

            return;
        }

        ERC20(baseToken).approve(settlementParams.contractAddress, sellAmount);

        uint256 quoteAmountFromUni = ISettlement(settlementParams.contractAddress).swapExactIn(
            quoteToken,
            baseToken,
            settlementParams.encodedData,
            sellAmount,
            settlementParams.maxQuoteAmount,
            address(this)
        );

        if (price > 0) {
            uint256 quoteAmount = sellAmount * price / Constants.Q96;

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
        SettlementParamsItem memory settlementParams,
        uint256 price,
        uint256 buyAmount
    ) internal {
        if (settlementParams.contractAddress == address(0)) {
            uint256 quoteAmount = buyAmount * price / Constants.Q96;

            ERC20(quoteToken).safeTransfer(msg.sender, quoteAmount);

            ERC20(baseToken).safeTransferFrom(msg.sender, address(this), buyAmount);

            return;
        }

        ERC20(quoteToken).approve(settlementParams.contractAddress, settlementParams.maxQuoteAmount);

        uint256 quoteAmountToUni = ISettlement(settlementParams.contractAddress).swapExactOut(
            quoteToken,
            baseToken,
            settlementParams.encodedData,
            buyAmount,
            settlementParams.maxQuoteAmount,
            address(this)
        );

        if (price > 0) {
            uint256 quoteAmount = buyAmount * price / Constants.Q96;

            if (quoteAmount > quoteAmountToUni) {
                ERC20(quoteToken).safeTransfer(msg.sender, quoteAmount - quoteAmountToUni);
            } else if (quoteAmountToUni > quoteAmount) {
                ERC20(quoteToken).safeTransferFrom(msg.sender, address(this), quoteAmountToUni - quoteAmount);
            }
        }
    }

    function quoteSettlement(SettlementParams memory settlementParams, int256 baseAmountDelta) external {
        int256 quoteAmount = -settlementParams.fee;

        if (baseAmountDelta > 0) {
            quoteAmount += _quoteSettlementLoop(settlementParams, true, uint256(baseAmountDelta));
        } else if (baseAmountDelta < 0) {
            quoteAmount += _quoteSettlementLoop(settlementParams, false, uint256(-baseAmountDelta));
        }

        _revertQuoteAmount(quoteAmount);
    }

    function _quoteSettlementLoop(SettlementParams memory settlementParams, bool isSell, uint256 baseAmountDelta)
        internal
        returns (int256 quoteAmount)
    {
        uint256 remain = baseAmountDelta;

        for (uint256 i = 0; i < settlementParams.items.length; i++) {
            IFillerMarket.SettlementParamsItem memory item = settlementParams.items[i];

            uint256 baseAmount = item.partialBaseAmount;

            // if the item is the last item
            if (i == settlementParams.items.length - 1) {
                baseAmount = remain;
            }

            if (isSell) {
                quoteAmount += _quoteSell(item, settlementParams.price, baseAmount);
            } else {
                quoteAmount += _quoteBuy(item, settlementParams.price, baseAmount);
            }

            remain -= baseAmount;
        }
    }

    function _quoteSell(SettlementParamsItem memory settlementParams, uint256 price, uint256 sellAmount)
        internal
        returns (int256)
    {
        if (settlementParams.contractAddress == address(0)) {
            uint256 quoteAmount = sellAmount * price / Constants.Q96;

            return int256(quoteAmount);
        }

        uint256 quoteAmountFromUni =
            ISettlement(settlementParams.contractAddress).quoteSwapExactIn(settlementParams.encodedData, sellAmount);

        if (price == 0) {
            return int256(quoteAmountFromUni);
        } else {
            uint256 quoteAmount = sellAmount * price / Constants.Q96;

            return int256(quoteAmount);
        }
    }

    function _quoteBuy(SettlementParamsItem memory settlementParams, uint256 price, uint256 buyAmount)
        internal
        returns (int256)
    {
        if (settlementParams.contractAddress == address(0)) {
            uint256 quoteAmount = buyAmount * price / Constants.Q96;

            return -int256(quoteAmount);
        }

        uint256 quoteAmountToUni =
            ISettlement(settlementParams.contractAddress).quoteSwapExactOut(settlementParams.encodedData, buyAmount);

        if (price == 0) {
            return -int256(quoteAmountToUni);
        } else {
            uint256 quoteAmount = buyAmount * price / Constants.Q96;

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
