// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import "../interfaces/ILendingPool.sol";
import "./BaseSettlement.sol";
import {Constants} from "../libraries/Constants.sol";

contract DirectSettlement is BaseSettlement {
    using SafeTransferLib for ERC20;

    struct SettlementParams {
        address quoteTokenAddress;
        address baseTokenAddress;
        uint256 price;
    }

    address immutable _filler;

    constructor(ILendingPool predyPool, address filler) BaseSettlement(predyPool) {
        _filler = filler;
    }

    function getSettlementParams(address quoteTokenAddress, address baseTokenAddress, uint256 price)
        external
        view
        returns (ISettlement.SettlementData memory)
    {
        return ISettlement.SettlementData(
            address(this), abi.encode(SettlementParams(quoteTokenAddress, baseTokenAddress, price))
        );
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta)
        external
        override(BaseSettlement)
    {
        if (address(_predyPool) != msg.sender) revert CallerIsNotLendingPool();

        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        if (baseAmountDelta > 0) {
            uint256 quoteAmount = uint256(baseAmountDelta) * settlemendParams.price / Constants.Q96;

            _predyPool.take(false, _filler, uint256(baseAmountDelta));

            ERC20(settlemendParams.quoteTokenAddress).safeTransferFrom(_filler, address(_predyPool), quoteAmount);
        } else if (baseAmountDelta < 0) {
            uint256 quoteAmount = uint256(-baseAmountDelta) * settlemendParams.price / Constants.Q96;

            _predyPool.take(true, _filler, quoteAmount);

            ERC20(settlemendParams.baseTokenAddress).safeTransferFrom(
                _filler, address(_predyPool), uint256(-baseAmountDelta)
            );
        }
    }

    function quoteSettlement(bytes memory settlementData, int256 baseAmountDelta) external pure override {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));
        int256 quoteAmount;

        if (baseAmountDelta > 0) {
            quoteAmount = int256(uint256(baseAmountDelta) * settlemendParams.price / Constants.Q96);
        } else if (baseAmountDelta < 0) {
            quoteAmount = -int256(uint256(-baseAmountDelta) * settlemendParams.price / Constants.Q96);
        }

        _revertQuoteAmount(quoteAmount);
    }
}
