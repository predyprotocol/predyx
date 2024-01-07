// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {IPredyPool} from "../interfaces/IPredyPool.sol";
import {ISettlement} from "../interfaces/ISettlement.sol";
import {Constants} from "../libraries/Constants.sol";
import {Math} from "../libraries/math/Math.sol";
import {IFillerMarket} from "../interfaces/IFillerMarket.sol";

library SettlementCallbackLib {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    struct SettlementParams {
        address sender;
        uint256 price;
        int256 fee;
        IFillerMarket.SettlementParamsItem[] items;
    }

    function decodeParams(bytes memory settlementData) internal pure returns (SettlementParams memory) {
        return abi.decode(settlementData, (SettlementParams));
    }

    function validate(
        mapping(address settlementContractAddress => bool) storage _whiteListedSettlements,
        SettlementParams memory settlementParams
    ) internal view {
        for (uint256 i = 0; i < settlementParams.items.length; i++) {
            IFillerMarket.SettlementParamsItem memory item = settlementParams.items[i];

            if (item.contractAddress != address(0) && !_whiteListedSettlements[item.contractAddress]) {
                revert IFillerMarket.SettlementContractIsNotWhitelisted();
            }
        }
    }

    function execSettlement(
        IPredyPool predyPool,
        address quoteToken,
        address baseToken,
        SettlementParams memory settlementParams,
        int256 baseAmountDelta
    ) internal {
        if (settlementParams.fee < 0) {
            ERC20(quoteToken).safeTransferFrom(
                settlementParams.sender, address(predyPool), uint256(-settlementParams.fee)
            );
        }

        execSettlementInternal(predyPool, quoteToken, baseToken, settlementParams, baseAmountDelta);

        if (settlementParams.fee > 0) {
            predyPool.take(true, settlementParams.sender, uint256(settlementParams.fee));
        }
    }

    function execSettlementInternal(
        IPredyPool predyPool,
        address quoteToken,
        address baseToken,
        SettlementParams memory settlementParams,
        int256 baseAmountDelta
    ) internal {
        if (baseAmountDelta > 0) {
            execSettlementInternalLoop(
                predyPool, quoteToken, baseToken, settlementParams, true, uint256(baseAmountDelta)
            );
        } else if (baseAmountDelta < 0) {
            execSettlementInternalLoop(
                predyPool, quoteToken, baseToken, settlementParams, false, uint256(-baseAmountDelta)
            );
        }
    }

    function execSettlementInternalLoop(
        IPredyPool predyPool,
        address quoteToken,
        address baseToken,
        SettlementParams memory settlementParams,
        bool isSell,
        uint256 baseAmountDelta
    ) internal {
        uint256 remain = baseAmountDelta;

        for (uint256 i = 0; i < settlementParams.items.length; i++) {
            IFillerMarket.SettlementParamsItem memory item = settlementParams.items[i];

            uint256 baseAmount = item.partialBaseAmount;

            // if the item is the last item
            if (i == settlementParams.items.length - 1) {
                baseAmount = remain;
            }

            if (isSell) {
                sell(
                    predyPool, quoteToken, baseToken, item, settlementParams.sender, settlementParams.price, baseAmount
                );
            } else {
                buy(predyPool, quoteToken, baseToken, item, settlementParams.sender, settlementParams.price, baseAmount);
            }

            remain -= baseAmount;
        }
    }

    function sell(
        IPredyPool predyPool,
        address quoteToken,
        address baseToken,
        IFillerMarket.SettlementParamsItem memory settlementParamsItem,
        address sender,
        uint256 price,
        uint256 sellAmount
    ) internal {
        if (settlementParamsItem.contractAddress == address(0)) {
            // direct fill
            uint256 quoteAmount = sellAmount * price / Constants.Q96;

            predyPool.take(false, sender, sellAmount);

            ERC20(quoteToken).safeTransferFrom(sender, address(predyPool), quoteAmount);

            return;
        }

        predyPool.take(false, address(this), sellAmount);
        ERC20(baseToken).approve(address(settlementParamsItem.contractAddress), sellAmount);

        uint256 quoteAmountFromUni = ISettlement(settlementParamsItem.contractAddress).swapExactIn(
            quoteToken,
            baseToken,
            settlementParamsItem.encodedData,
            sellAmount,
            settlementParamsItem.maxQuoteAmount,
            address(this)
        );

        if (price == 0) {
            ERC20(quoteToken).safeTransfer(address(predyPool), quoteAmountFromUni);
        } else {
            uint256 quoteAmount = sellAmount * price / Constants.Q96;

            if (quoteAmount > quoteAmountFromUni) {
                ERC20(quoteToken).safeTransferFrom(sender, address(this), quoteAmount - quoteAmountFromUni);
            } else if (quoteAmountFromUni > quoteAmount) {
                ERC20(quoteToken).safeTransfer(sender, quoteAmountFromUni - quoteAmount);
            }

            ERC20(quoteToken).safeTransfer(address(predyPool), quoteAmount);
        }
    }

    function buy(
        IPredyPool predyPool,
        address quoteToken,
        address baseToken,
        IFillerMarket.SettlementParamsItem memory settlementParamsItem,
        address sender,
        uint256 price,
        uint256 buyAmount
    ) internal {
        if (settlementParamsItem.contractAddress == address(0)) {
            // direct fill
            uint256 quoteAmount = buyAmount * price / Constants.Q96;

            predyPool.take(true, sender, quoteAmount);

            ERC20(baseToken).safeTransferFrom(sender, address(predyPool), buyAmount);

            return;
        }

        predyPool.take(true, address(this), settlementParamsItem.maxQuoteAmount);
        ERC20(quoteToken).approve(address(settlementParamsItem.contractAddress), settlementParamsItem.maxQuoteAmount);

        uint256 quoteAmountToUni = ISettlement(settlementParamsItem.contractAddress).swapExactOut(
            quoteToken,
            baseToken,
            settlementParamsItem.encodedData,
            buyAmount,
            settlementParamsItem.maxQuoteAmount,
            address(predyPool)
        );

        if (price == 0) {
            ERC20(quoteToken).safeTransfer(address(predyPool), settlementParamsItem.maxQuoteAmount - quoteAmountToUni);
        } else {
            uint256 quoteAmount = buyAmount * price / Constants.Q96;

            if (quoteAmount > quoteAmountToUni) {
                ERC20(quoteToken).safeTransfer(sender, quoteAmount - quoteAmountToUni);
            } else if (quoteAmountToUni > quoteAmount) {
                ERC20(quoteToken).safeTransferFrom(sender, address(this), quoteAmountToUni - quoteAmount);
            }

            ERC20(quoteToken).safeTransfer(address(predyPool), settlementParamsItem.maxQuoteAmount - quoteAmount);
        }
    }
}
