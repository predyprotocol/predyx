// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/types/GlobalData.sol";
import "../../src/interfaces/IPredyPool.sol";
import "../../src/interfaces/IHooks.sol";
import "../../src/libraries/logic/TradeLogic.sol";

/**
 * @notice Mock of ERC20 contract
 */
contract TestTradeMarket is IHooks {
    IPredyPool predyPool;

    struct SettlementParams {
        address quoteTokenAddress;
        address baseTokenAddress;
    }

    constructor(IPredyPool _predyPool) {
        predyPool = _predyPool;
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta) external {
        SettlementParams memory settlemendParams = abi.decode(settlementData, (SettlementParams));

        if (baseAmountDelta < 0) {
            uint256 quoteAmount = uint256(-baseAmountDelta);

            predyPool.take(1, false, address(this), uint256(-baseAmountDelta));

            IERC20(settlemendParams.quoteTokenAddress).transfer(address(predyPool), quoteAmount);

            predyPool.settle(1, true);
        } else {
            uint256 quoteAmount = uint256(baseAmountDelta);

            predyPool.take(1, true, address(this), quoteAmount);

            IERC20(settlemendParams.baseTokenAddress).transfer(address(predyPool), uint256(baseAmountDelta));

            predyPool.settle(1, false);
        }
    }

    function predyTradeAfterCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external {}
    function predyLiquidationCallback(
        IPredyPool.TradeParams memory tradeParams,
        IPredyPool.TradeResult memory tradeResult
    ) external {}

    function trade(uint256 pairId, IPredyPool.TradeParams memory tradeParams, bytes memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        return predyPool.trade(pairId, tradeParams, settlementData);
    }
}
