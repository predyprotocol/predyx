// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "./IPredyPool.sol";

interface IHooks {
    struct SettlementData {
        address settlementContractAddress;
        bytes encodedData;
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta) external;
    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external;
}
