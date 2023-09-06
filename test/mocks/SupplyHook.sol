// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {MockERC20} from "./MockERC20.sol";
import "../../src/PoolManager.sol";

contract SupplyHook {
    PoolManager public poolManager;

    struct SupplySignedOrder {
        uint256 pairId;
        bool isQuoteAsset;
        address tokenAddress;
        uint256 supplyAmount;
    }

    constructor(PoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function supply(uint256 pairId, bool isQuoteAsset, address tokenAddress, uint256 supplyAmount) external {
        bytes memory callbackData =
            abi.encode(SupplyHook.SupplySignedOrder(pairId, isQuoteAsset, tokenAddress, supplyAmount));

        MockERC20(tokenAddress).transferFrom(msg.sender, address(this), supplyAmount);

        poolManager.lockForSupply(callbackData);
    }

    function lockAquired(bytes memory data) external {
        SupplySignedOrder memory supplyOrder = abi.decode(data, (SupplySignedOrder));

        poolManager.supply(supplyOrder.pairId, supplyOrder.isQuoteAsset, supplyOrder.supplyAmount);

        MockERC20(supplyOrder.tokenAddress).transfer(address(poolManager), supplyOrder.supplyAmount);

        poolManager.settle(supplyOrder.pairId, supplyOrder.isQuoteAsset);
    }
}
