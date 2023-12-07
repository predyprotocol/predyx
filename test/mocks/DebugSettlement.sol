// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {ILendingPool} from "../../src/interfaces/ILendingPool.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {BaseSettlement} from "../../src/settlements/BaseSettlement.sol";

contract DebugSettlement is BaseSettlement {
    using SafeTransferLib for ERC20;

    struct SettlementParams {
        address quoteTokenAddress;
        address baseTokenAddress;
        uint256 quoteAmount;
        uint256 baseAmount;
    }

    address private immutable _filler;

    constructor(ILendingPool predyPool, address filler) BaseSettlement(predyPool) {
        _filler = filler;
    }

    function getSettlementParams(
        address quoteTokenAddress,
        address baseTokenAddress,
        uint256 quoteAmount,
        uint256 baseAmount
    ) external view returns (ISettlement.SettlementData memory) {
        return ISettlement.SettlementData(
            address(this), abi.encode(SettlementParams(quoteTokenAddress, baseTokenAddress, quoteAmount, baseAmount))
        );
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta)
        external
        override(BaseSettlement)
    {
        if (address(_predyPool) != msg.sender) revert CallerIsNotLendingPool();

        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        if (baseAmountDelta > 0) {
            _predyPool.take(false, _filler, settlemendParams.baseAmount);

            ERC20(settlemendParams.quoteTokenAddress).safeTransferFrom(
                _filler, address(_predyPool), settlemendParams.quoteAmount
            );
        } else if (baseAmountDelta < 0) {
            _predyPool.take(true, _filler, settlemendParams.quoteAmount);

            ERC20(settlemendParams.baseTokenAddress).safeTransferFrom(
                _filler, address(_predyPool), settlemendParams.baseAmount
            );
        }
    }

    function quoteSettlement(bytes memory, int256) external pure override {
        _revertQuoteAmount(0);
    }
}
