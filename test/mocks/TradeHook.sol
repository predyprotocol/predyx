// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {MockERC20} from "./MockERC20.sol";
import "../../src/PoolManager.sol";

contract TradeHook {
    PoolManager public poolManager;

    struct TradeSignedOrder {
        int256 tradeAmount;
        uint256 limitPrice;
    }

    struct SettleCallbackParams {
        address currency0;
        address currency1;
    }

    constructor(PoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function trade(uint256 pairId, uint256 vaultId, int256 tradeAmount, address currency0, address currency1)
        external
    {
        IPoolManager.SignedOrder[] memory orders = new IPoolManager.SignedOrder[](1);

        TradeSignedOrder memory tradeOrder = TradeHook.TradeSignedOrder(tradeAmount, 0);

        orders[0] = IPoolManager.SignedOrder(vaultId, abi.encode(tradeOrder), 0);

        bytes memory callbackData = abi.encode(TradeHook.SettleCallbackParams(currency0, currency1));

        poolManager.lock(pairId, orders, callbackData);
    }

    function lockAquired(IPoolManager.SignedOrder memory order) external {
        TradeSignedOrder memory tradeOrder = abi.decode(order.data, (TradeSignedOrder));

        poolManager.prepareTradePerpPosition(order.vaultId, tradeOrder.tradeAmount);
    }

    function postLockAquired(IPoolManager.SignedOrder memory order, IPoolManager.LockData memory lockData) external {
        TradeSignedOrder memory tradeOrder = abi.decode(order.data, (TradeSignedOrder));

        poolManager.postTradePerpPosition(order.vaultId, -lockData.quoteDelta);
    }

    function settleCallback(bytes memory callbackData, IPoolManager.LockData memory lockData) public {
        SettleCallbackParams memory settleCallbackParams = abi.decode(callbackData, (SettleCallbackParams));

        int256 amount0 = lockData.baseDelta;

        // TODO: swap
        int256 amount1 = amount0;

        // TODO: with buffer
        poolManager.take(true, address(this), uint256(amount1));

        MockERC20(settleCallbackParams.currency0).transfer(address(poolManager), uint256(amount0));

        poolManager.settle(false);
    }
}
