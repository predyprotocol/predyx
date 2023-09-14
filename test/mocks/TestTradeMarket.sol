// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/types/GlobalData.sol";
import "../../src/interfaces/IPredyPool.sol";
import "../../src/base/BaseHookCallback.sol";
import "../../src/libraries/logic/TradeLogic.sol";

/**
 * @notice A mock market contract for trade tests
 */
abstract contract BaseTestTradeMarket is BaseHookCallback {
    constructor(IPredyPool _predyPool) BaseHookCallback(_predyPool) {
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta) external virtual override(BaseHookCallback) {
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external virtual override(BaseHookCallback) {}

    function predyLiquidationCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external virtual override(BaseHookCallback) {}

    function trade(uint256 pairId, IPredyPool.TradeParams memory tradeParams, bytes memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        return predyPool.trade(pairId, tradeParams, settlementData);
    }
}

contract TestTradeMarket is BaseTestTradeMarket {
    struct SettlementParams {
        address quoteTokenAddress;
        address baseTokenAddress;
    }

    constructor(IPredyPool _predyPool) BaseTestTradeMarket(_predyPool) {
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta) external override(BaseTestTradeMarket) {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        if (baseAmountDelta > 0) {
            uint256 quoteAmount = uint256(baseAmountDelta);

            predyPool.take(settlemendParams.baseTokenAddress, address(this), uint256(baseAmountDelta));

            IERC20(settlemendParams.quoteTokenAddress).transfer(address(predyPool), quoteAmount);

            predyPool.settle(true);
        } else {
            uint256 quoteAmount = uint256(-baseAmountDelta);

            predyPool.take(settlemendParams.quoteTokenAddress, address(this), quoteAmount);

            IERC20(settlemendParams.baseTokenAddress).transfer(address(predyPool), uint256(-baseAmountDelta));

            predyPool.settle(false);
        }
    }
}


contract TestTradeMarket2 is BaseTestTradeMarket {

    struct SettlementParams {
        uint256 takeAmount;
        uint256 settleAmount;
        address takeTokenAddress;
        address settleTokenAddress;
        bool settleIsQuoteAsset;
    }

    constructor(IPredyPool _predyPool) BaseTestTradeMarket(_predyPool) {
    }

    function predySettlementCallback(bytes memory settlementData, int256) external override(BaseTestTradeMarket) {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        predyPool.take(settlemendParams.takeTokenAddress, address(this), settlemendParams.takeAmount);

        IERC20(settlemendParams.settleTokenAddress).transfer(address(predyPool), settlemendParams.settleAmount);

        predyPool.settle(settlemendParams.settleIsQuoteAsset);
    }
}
