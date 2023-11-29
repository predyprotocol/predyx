// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/settlements/BaseSettlement.sol";
import {IPredyPool} from "../../src/interfaces/IPredyPool.sol";

contract TestSettlementCurrencyNotSettled is BaseSettlement {
    struct SettlementParams {
        address baseTokenAddress;
        address settleTokenAddress;
        int256 takeAmount;
        int256 settleAmount;
    }

    constructor(ILendingPool predyPool) BaseSettlement(predyPool) {}

    function predySettlementCallback(bytes memory settlementData, int256) external override(BaseSettlement) {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        if (settlemendParams.takeAmount >= 0) {
            _predyPool.take(false, address(this), uint256(settlemendParams.takeAmount));
        } else {
            IERC20(settlemendParams.baseTokenAddress).transfer(
                address(_predyPool), uint256(-settlemendParams.takeAmount)
            );
        }

        if (settlemendParams.settleAmount >= 0) {
            _predyPool.take(true, address(this), uint256(settlemendParams.settleAmount));
        } else {
            IERC20(settlemendParams.settleTokenAddress).transfer(
                address(_predyPool), uint256(-settlemendParams.settleAmount)
            );
        }
    }
}

contract TestSettlementReentrant is BaseSettlement {
    struct SettlementParams {
        address settleTokenAddress;
        uint256 takeAmount;
        uint256 settleAmount;
        IPredyPool.TradeParams tradeParams;
        ISettlement.SettlementData settlementData;
    }

    constructor(ILendingPool predyPool) BaseSettlement(predyPool) {}

    function predySettlementCallback(bytes memory settlementData, int256) external override(BaseSettlement) {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        _predyPool.take(false, address(this), settlemendParams.takeAmount);

        IERC20(settlemendParams.settleTokenAddress).transfer(address(_predyPool), settlemendParams.settleAmount);

        IPredyPool(address(_predyPool)).trade(settlemendParams.tradeParams, settlemendParams.settlementData);
    }
}
