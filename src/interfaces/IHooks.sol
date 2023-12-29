// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

import "./IPredyPool.sol";

interface IHooks {
    function predySettlementCallback(
        address quoteToken,
        address baseToken,
        bytes memory settlementData,
        int256 baseAmountDelta
    ) external;

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external;

    function payCallback(address token, uint256 amount, address sender) external;
}
