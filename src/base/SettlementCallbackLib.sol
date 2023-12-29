// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {IPredyPool} from "../interfaces/IPredyPool.sol";
import {ISettlement} from "../interfaces/ISettlement.sol";
import {Constants} from "../libraries/Constants.sol";
import {Math} from "../libraries/math/Math.sol";
import "forge-std/console.sol";

library SettlementCallbackLib {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    struct SettlementParams {
        address sender;
        address contractAddress;
        bytes encodedData;
        uint256 maxQuoteAmount;
        uint256 price;
        int256 fee;
    }

    function _execSettlement(
        IPredyPool predyPool,
        address quoteToken,
        address baseToken,
        bytes memory settlementData,
        int256 baseAmountDelta
    ) internal {
        // TODO: sender must be market
        SettlementParams memory settlementParams = abi.decode(settlementData, (SettlementParams));

        if (settlementParams.fee < 0) {
            ERC20(quoteToken).safeTransferFrom(settlementParams.sender, address(this), uint256(-settlementParams.fee));
        }

        _execSettlementInternal(predyPool, quoteToken, baseToken, settlementParams, baseAmountDelta);

        if (settlementParams.fee > 0) {
            ERC20(quoteToken).safeTransfer(settlementParams.sender, uint256(settlementParams.fee));
        }
    }

    function _execSettlementInternal(
        IPredyPool predyPool,
        address quoteToken,
        address baseToken,
        SettlementParams memory settlementParams,
        int256 baseAmountDelta
    ) internal {
        if (baseAmountDelta > 0) {
            if (settlementParams.contractAddress == address(0)) {
                uint256 quoteAmount = uint256(baseAmountDelta) * settlementParams.price / Constants.Q96;

                predyPool.take(false, settlementParams.sender, uint256(baseAmountDelta));

                ERC20(quoteToken).safeTransferFrom(settlementParams.sender, address(predyPool), quoteAmount);

                return;
            }

            predyPool.take(false, settlementParams.contractAddress, uint256(baseAmountDelta));

            uint256 quoteAmountFromUni = ISettlement(settlementParams.contractAddress).swapExactIn(
                quoteToken, baseToken, settlementParams.encodedData, uint256(baseAmountDelta), 0, address(this)
            );

            if (settlementParams.price == 0) {
                ERC20(quoteToken).safeTransfer(address(predyPool), quoteAmountFromUni.addDelta(-settlementParams.fee));
            } else {
                uint256 quoteAmount = uint256(baseAmountDelta) * settlementParams.price / Constants.Q96;

                if (quoteAmount > quoteAmountFromUni) {
                    ERC20(quoteToken).safeTransferFrom(
                        settlementParams.sender, address(this), quoteAmount - quoteAmountFromUni
                    );
                } else if (quoteAmountFromUni > quoteAmount) {
                    ERC20(quoteToken).safeTransfer(settlementParams.sender, quoteAmountFromUni - quoteAmount);
                }

                ERC20(quoteToken).safeTransfer(address(predyPool), quoteAmount);
            }
        } else if (baseAmountDelta < 0) {
            if (settlementParams.contractAddress == address(0)) {
                uint256 quoteAmount = uint256(-baseAmountDelta) * settlementParams.price / Constants.Q96;

                predyPool.take(true, settlementParams.sender, quoteAmount);

                ERC20(baseToken).safeTransferFrom(
                    settlementParams.sender, address(predyPool), uint256(-baseAmountDelta)
                );

                return;
            }

            predyPool.take(true, settlementParams.contractAddress, settlementParams.maxQuoteAmount);

            uint256 quoteAmountToUni = ISettlement(settlementParams.contractAddress).swapExactOut(
                quoteToken,
                baseToken,
                settlementParams.encodedData,
                uint256(-baseAmountDelta),
                settlementParams.maxQuoteAmount,
                address(predyPool)
            );

            if (settlementParams.price == 0) {
                ERC20(quoteToken).safeTransfer(
                    address(predyPool),
                    settlementParams.maxQuoteAmount - quoteAmountToUni.addDelta(settlementParams.fee)
                );
            } else {
                uint256 quoteAmount = uint256(-baseAmountDelta) * settlementParams.price / Constants.Q96;

                if (quoteAmount > quoteAmountToUni) {
                    ERC20(quoteToken).safeTransfer(settlementParams.sender, quoteAmount - quoteAmountToUni);
                } else if (quoteAmountToUni > quoteAmount) {
                    ERC20(quoteToken).safeTransferFrom(
                        settlementParams.sender, address(this), quoteAmountToUni - quoteAmount
                    );
                }

                ERC20(quoteToken).safeTransfer(address(predyPool), settlementParams.maxQuoteAmount - quoteAmount);
            }
        }
    }
}
