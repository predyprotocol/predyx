// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/settlements/BaseSettlement.sol";

contract TestSettlementCurrencyNotSettled is BaseSettlement {
    struct SettlementParams {
        address settleTokenAddress;
        uint256 takeAmount;
        uint256 settleAmount;
    }

    constructor(IPredyPool predyPool) BaseSettlement(predyPool) {}

    function predySettlementCallback(bytes memory settlementData, int256) external override(BaseSettlement) {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        _predyPool.take(false, address(this), settlemendParams.takeAmount);

        IERC20(settlemendParams.settleTokenAddress).transfer(address(_predyPool), settlemendParams.settleAmount);
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

    constructor(IPredyPool predyPool) BaseSettlement(predyPool) {}

    function predySettlementCallback(bytes memory settlementData, int256) external override(BaseSettlement) {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        _predyPool.take(false, address(this), settlemendParams.takeAmount);

        IERC20(settlemendParams.settleTokenAddress).transfer(address(_predyPool), settlemendParams.settleAmount);

        _predyPool.trade(settlemendParams.tradeParams, settlemendParams.settlementData);
    }
}
