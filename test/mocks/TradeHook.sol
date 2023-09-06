// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {MockERC20} from "./MockERC20.sol";
import "../../src/PoolManager.sol";

contract TradeHook {
    PoolManager public poolManager;

    uint256 taleMockAmount;

    struct SettleCallbackParams {
        uint256 pairId;
        address currency0;
        address currency1;
    }

    constructor(PoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function setTakeMockAmount(uint256 _mockData) external {
        taleMockAmount = _mockData;
    }

    function trade(
        uint256 pairId,
        uint256 vaultId,
        int256 tradeAmount,
        int256 limitPrice,
        address currency0,
        address currency1
    ) external {
        IPoolManager.SignedOrder[] memory orders = new IPoolManager.SignedOrder[](1);

        orders[0] = IPoolManager.SignedOrder(pairId, vaultId, tradeAmount, limitPrice, 0);

        bytes memory callbackData = abi.encode(TradeHook.SettleCallbackParams(pairId, currency0, currency1));

        poolManager.lockForTrade(pairId, orders, callbackData);
    }

    function settleCallback(bytes memory callbackData, int256 baseAmountDelta) public {
        SettleCallbackParams memory settleCallbackParams = abi.decode(callbackData, (SettleCallbackParams));

        if (baseAmountDelta > 0) {
            uint256 settleAmount = uint256(baseAmountDelta);

            uint256 takeAmount = settleAmount;

            // TODO: with buffer
            if (taleMockAmount > 0) {
                takeAmount = taleMockAmount;
            }
            poolManager.take(true, address(this), takeAmount);

            MockERC20(settleCallbackParams.currency0).transfer(address(poolManager), settleAmount);

            poolManager.settle(settleCallbackParams.pairId, false);
        } else {
            uint256 takeAmount = uint256(-baseAmountDelta);

            uint256 settleAmount = takeAmount;

            // TODO: with buffer
            if (taleMockAmount > 0) {
                settleAmount = taleMockAmount;
            }

            poolManager.take(false, address(this), takeAmount);

            MockERC20(settleCallbackParams.currency1).transfer(address(poolManager), settleAmount);

            poolManager.settle(settleCallbackParams.pairId, true);
        }
    }

    function afterTrade(IPoolManager.SignedOrder memory order) external {
        // nothing todo
    }
}
