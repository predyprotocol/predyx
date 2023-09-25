// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IPredyPool.sol";
import "./BaseSettlement.sol";

contract DirectSettlement is BaseSettlement {
    uint256 _price;

    struct SettlementParams {
        address quoteTokenAddress;
        address baseTokenAddress;
        uint256 price;
    }

    constructor(IPredyPool _predyPool) BaseSettlement(_predyPool) {
        _price = 1e4;
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
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        if (baseAmountDelta > 0) {
            uint256 quoteAmount = uint256(baseAmountDelta) * settlemendParams.price / 1e4;

            _predyPool.take(false, address(this), uint256(baseAmountDelta));

            IERC20(settlemendParams.quoteTokenAddress).transfer(address(_predyPool), quoteAmount);
        } else if (baseAmountDelta < 0) {
            uint256 quoteAmount = uint256(-baseAmountDelta) * settlemendParams.price / 1e4;

            _predyPool.take(true, address(this), quoteAmount);

            IERC20(settlemendParams.baseTokenAddress).transfer(address(_predyPool), uint256(-baseAmountDelta));
        }
    }
}
