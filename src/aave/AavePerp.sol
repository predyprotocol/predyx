// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./IPool.sol";
import "../interfaces/IPredyPool.sol";
import "../interfaces/ISettlement.sol";
import "../interfaces/IFillerMarket.sol";
import "../libraries/orders/PerpOrder.sol";

contract AavePerp is IFillerMarket {
    IPool internal _pool;

    struct UserPosition {
        int256 positionAmount;
        int256 entrryValue;
    }

    struct MarketStatus {
        uint256 totalSupply;
        uint256 totalBorrow;
    }

    MarketStatus internal _marketStatus;


    constructor(IPool pool) {
        _pool = pool;
    }

    function depositToInsurancePool() external {

    }

    function withdrawFromInsurancePool() external {

    }

    function executeOrder(address filler, SignedOrder memory order, ISettlement.SettlementData memory settlementData) external {
        PerpOrder memory perpOrder = abi.decode(order.order, (PerpOrder));

        // calculate fee

        // swap
        int256 quoteAmount = _swap(perpOrder.tradeAmount, settlementData);

        if(perpOrder.tradeAmount > 0) {
            _pool.supply(asset, uint256(perpOrder.tradeAmount), onBehalfOf, 0);
            _pool.borrow(asset, uint256(-quoteAmount), 2, 0, onBehalfOf);
        } else {
            _pool.supply(asset, uint256(quoteAmount), onBehalfOf, 0);
            _pool.borrow(asset, uint256(-perpOrder.tradeAmount), 2, 0, onBehalfOf);
        }

        // TODO: updateMargin
        // TODO: supply

        // TODO: check position is safe
    }

    function execLiquidationCall() external {

    }

    function confirmLiquidation() external {
        
    }

    function close() external {

    }

    function _calculateFee() internal {
        _marketStatus.totalSupply

        _pool.supply(asset, uint256(quoteAmount), onBehalfOf, 0);

    }

    function _swap(
        int256 baseAmount,
        ISettlement.SettlementData memory settlementData
    ) internal returns (int256 quoteAmount) {
        if (baseAmount == 0) {
            int256 amountStable = int256(calculateStableAmount(sqrtPrice, 1e18));

            return divToStable(swapParams, int256(1e18), amountStable, 0);
        }

        globalData.initializeLock(pairId, settlementData.settlementContractAddress);

        ISettlement(settlementData.settlementContractAddress).predySettlementCallback(
            settlementData.encodedData, baseAmount
        );

        quoteAmount = globalData.settle(true);

        if (globalData.settle(false) != -baseAmount) {
            revert IPredyPool.CurrencyNotSettled();
        }

        // TODO: in case of baseAmount == 0,
        if (quoteAmount * baseAmount <= 0) {
            revert IPredyPool.CurrencyNotSettled();
        }

        delete globalData.lockData;
    }
}
