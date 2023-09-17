// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../src/types/GlobalData.sol";
import "../../src/interfaces/IPredyPool.sol";
import "../../src/base/BaseHookCallback.sol";
import "../../src/libraries/logic/TradeLogic.sol";

/**
 * @notice A mock market contract for trade tests
 */
abstract contract BaseTestTradeMarket is BaseHookCallback {
    constructor(IPredyPool _predyPool) BaseHookCallback(_predyPool) {}

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta)
        external
        virtual
        override(BaseHookCallback)
    {}

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external virtual override(BaseHookCallback) {}

    function predyLiquidationCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external virtual override(BaseHookCallback) {}

    function trade(IPredyPool.TradeParams memory tradeParams, bytes memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        return predyPool.trade(tradeParams, settlementData);
    }

    function execLiquidationCall(uint256 vaultId, uint256 closeRatio, bytes memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        return predyPool.execLiquidationCall(vaultId, closeRatio, settlementData);
    }
}

contract TestTradeMarket is BaseTestTradeMarket {
    struct TradeAfterParams {
        address quoteTokenAddress;
        uint256 marginAmountUpdate;
    }

    struct SettlementParams {
        address quoteTokenAddress;
        address baseTokenAddress;
    }

    constructor(IPredyPool _predyPool) BaseTestTradeMarket(_predyPool) {}

    function predyTradeAfterCallback(IPredyPool.TradeParams memory tradeParams, IPredyPool.TradeResult memory)
        external
        override(BaseTestTradeMarket)
    {
        TradeAfterParams memory tradeAfterParams = abi.decode(tradeParams.extraData, (TradeAfterParams));
        IERC20(tradeAfterParams.quoteTokenAddress).transfer(address(predyPool), tradeAfterParams.marginAmountUpdate);
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta)
        external
        override(BaseTestTradeMarket)
    {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        if (baseAmountDelta > 0) {
            uint256 quoteAmount = uint256(baseAmountDelta);

            predyPool.take(false, address(this), uint256(baseAmountDelta));

            IERC20(settlemendParams.quoteTokenAddress).transfer(address(predyPool), quoteAmount);
        } else {
            uint256 quoteAmount = uint256(-baseAmountDelta);

            predyPool.take(true, address(this), quoteAmount);

            IERC20(settlemendParams.baseTokenAddress).transfer(address(predyPool), uint256(-baseAmountDelta));
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

    constructor(IPredyPool _predyPool) BaseTestTradeMarket(_predyPool) {}

    function predySettlementCallback(bytes memory settlementData, int256) external override(BaseTestTradeMarket) {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        predyPool.take(false, address(this), settlemendParams.takeAmount);

        IERC20(settlemendParams.settleTokenAddress).transfer(address(predyPool), settlemendParams.settleAmount);
    }
}
