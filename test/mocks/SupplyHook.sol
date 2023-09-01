// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {MockERC20} from "./MockERC20.sol";
import "../../src/PoolManager.sol";

contract SupplyHook {
    PoolManager public poolManager;

    struct SupplySignedOrder {
        bool isQuoteAsset;
        address tokenAddress;
        uint256 supplyAmount;
    }

    constructor(PoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function supply(uint256 pairId, bool isQuoteAsset, address tokenAddress, uint256 supplyAmount) external {
        IPoolManager.SignedOrder[] memory orders = new IPoolManager.SignedOrder[](1);

        orders[0] = IPoolManager.SignedOrder(
            0, abi.encode(SupplyHook.SupplySignedOrder(isQuoteAsset, tokenAddress, supplyAmount)), 0
        );

        bytes memory callbackData = abi.encode(SupplyHook.SupplySignedOrder(isQuoteAsset, tokenAddress, supplyAmount));

        MockERC20(tokenAddress).transferFrom(msg.sender, address(this), supplyAmount);

        poolManager.lock(pairId, orders, callbackData);
    }

    function lockAquired(IPoolManager.SignedOrder memory order) external {
        SupplySignedOrder memory supplyOrder = abi.decode(order.data, (SupplySignedOrder));

        poolManager.supply(supplyOrder.isQuoteAsset, supplyOrder.supplyAmount);
    }

    function settleCallback(bytes memory callbackData, IPoolManager.LockData memory lockData) public {
        SupplySignedOrder memory supplyOrder = abi.decode(callbackData, (SupplySignedOrder));

        MockERC20(supplyOrder.tokenAddress).transfer(address(poolManager), supplyOrder.supplyAmount);

        poolManager.settle(supplyOrder.isQuoteAsset);
    }

    function postLockAquired(IPoolManager.SignedOrder memory order, IPoolManager.LockData memory lockData) external {}
}
