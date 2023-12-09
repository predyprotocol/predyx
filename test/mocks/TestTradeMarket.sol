// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import "../../src/types/GlobalData.sol";
import "../../src/interfaces/IPredyPool.sol";
import "../../src/base/BaseHookCallback.sol";
import "../../src/settlements/BaseSettlement.sol";
import "../../src/libraries/logic/TradeLogic.sol";

/**
 * @notice A mock market contract for trade tests
 */
contract TestTradeMarket is BaseHookCallback {
    struct TradeAfterParams {
        address trader;
        address quoteTokenAddress;
        uint256 marginAmountUpdate;
    }

    constructor(IPredyPool predyPool) BaseHookCallback(predyPool) {}

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external override(BaseHookCallback) {
        TradeAfterParams memory tradeAfterParams = abi.decode(tradeParams.extraData, (TradeAfterParams));

        if (tradeResult.minMargin == 0) {
            DataType.Vault memory vault = _predyPool.getVault(tradeParams.vaultId);

            ILendingPool(address(_predyPool)).take(true, tradeAfterParams.trader, uint256(vault.margin));
        } else {
            ERC20(tradeAfterParams.quoteTokenAddress).transfer(address(_predyPool), tradeAfterParams.marginAmountUpdate);
        }
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
