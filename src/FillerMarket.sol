// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./interfaces/IPredyPool.sol";
import "./interfaces/IFillerMarket.sol";
import "./interfaces/IHooks.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FillerMarket is IFillerMarket, IHooks {
    function predySettlementCallback(bytes memory settlementData, int256 quoteAmountDelta, int256 baseAmountDelta)
        external
    {}

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external {}

    function predyLiquidationCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external {}

    function trade(SignedOrder memory order, bytes memory settlementData) external {}

    function execLiquidationCall(uint256 positionId, bytes memory settlementData) external {}

    function depositToFillerPool(uint256 depositAmount) external {}

    function withdrawFromFillerPool(uint256 withdrawAmount) external {}

    function getPositionStatus(uint256 positionId) external {}
}
