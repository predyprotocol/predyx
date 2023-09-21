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
    constructor(IPredyPool predyPool) BaseHookCallback(predyPool) {}

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
        IPredyPool.TradeResult memory tradeResult,
        int256 marginAmount
    ) external virtual override(BaseHookCallback) {}

    function trade(IPredyPool.TradeParams memory tradeParams, bytes memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        return _predyPool.trade(tradeParams, settlementData);
    }

    function execLiquidationCall(uint256 vaultId, uint256 closeRatio, bytes memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        return _predyPool.execLiquidationCall(vaultId, closeRatio, settlementData);
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

    uint256 _price;

    constructor(IPredyPool _predyPool) BaseTestTradeMarket(_predyPool) {
        _price = 1e4;
    }

    function setMockPrice(uint256 price) external {
        _price = price;
    }

    function predyTradeAfterCallback(IPredyPool.TradeParams memory tradeParams, IPredyPool.TradeResult memory)
        external
        override(BaseTestTradeMarket)
    {
        TradeAfterParams memory tradeAfterParams = abi.decode(tradeParams.extraData, (TradeAfterParams));
        IERC20(tradeAfterParams.quoteTokenAddress).transfer(address(_predyPool), tradeAfterParams.marginAmountUpdate);
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta)
        external
        override(BaseTestTradeMarket)
    {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        if (baseAmountDelta > 0) {
            uint256 quoteAmount = uint256(baseAmountDelta) * _price / 1e4;

            _predyPool.take(false, address(this), uint256(baseAmountDelta));

            IERC20(settlemendParams.quoteTokenAddress).transfer(address(_predyPool), quoteAmount);
        } else {
            uint256 quoteAmount = uint256(-baseAmountDelta) * _price / 1e4;

            _predyPool.take(true, address(this), quoteAmount);

            IERC20(settlemendParams.baseTokenAddress).transfer(address(_predyPool), uint256(-baseAmountDelta));
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

        _predyPool.take(false, address(this), settlemendParams.takeAmount);

        IERC20(settlemendParams.settleTokenAddress).transfer(address(_predyPool), settlemendParams.settleAmount);
    }
}
