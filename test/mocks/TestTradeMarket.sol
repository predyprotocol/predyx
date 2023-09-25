// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../src/types/GlobalData.sol";
import "../../src/interfaces/IPredyPool.sol";
import "../../src/base/BaseHookCallback.sol";
import "../../src/libraries/logic/TradeLogic.sol";

/**
 * @notice A mock market contract for trade tests
 */
contract TestTradeMarket is BaseHookCallback, ISettlement {
    struct TradeAfterParams {
        address quoteTokenAddress;
        uint256 marginAmountUpdate;
    }

    struct SettlementParams {
        address settleTokenAddress;
        uint256 takeAmount;
        uint256 settleAmount;
    }

    constructor(IPredyPool predyPool) BaseHookCallback(predyPool) {}

    function predyTradeAfterCallback(IPredyPool.TradeParams memory tradeParams, IPredyPool.TradeResult memory)
        external
        override(BaseHookCallback)
    {
        TradeAfterParams memory tradeAfterParams = abi.decode(tradeParams.extraData, (TradeAfterParams));
        IERC20(tradeAfterParams.quoteTokenAddress).transfer(address(_predyPool), tradeAfterParams.marginAmountUpdate);
    }

    function predySettlementCallback(bytes memory settlementData, int256) external override(ISettlement) {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        _predyPool.take(false, address(this), settlemendParams.takeAmount);

        IERC20(settlemendParams.settleTokenAddress).transfer(address(_predyPool), settlemendParams.settleAmount);
    }

    function trade(IPredyPool.TradeParams memory tradeParams, ISettlement.SettlementData memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        return _predyPool.trade(tradeParams, settlementData);
    }

    function execLiquidationCall(uint256 vaultId, uint256 closeRatio, ISettlement.SettlementData memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        return _predyPool.execLiquidationCall(vaultId, closeRatio, settlementData);
    }
}
