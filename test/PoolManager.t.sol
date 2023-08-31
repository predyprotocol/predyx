// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "../src/PoolManager.sol";

contract SupplyHook {
    PoolManager public poolManager;

    struct SupplySignedOrder {
        address currency;
        uint256 supplyAmount;
    }

    constructor(
        PoolManager _poolManager
    ) {
        poolManager = _poolManager;
    }

    function supply(
        address currency,
        uint256 supplyAmount
    ) external {
        IPoolManager.SignedOrder[] memory orders = new IPoolManager.SignedOrder[](1);

        orders[0] = IPoolManager.SignedOrder(
            0,
            abi.encode(SupplyHook.SupplySignedOrder(currency, supplyAmount)),
            0
        );

        bytes memory callbackData = abi.encode(SupplyHook.SupplySignedOrder(currency, supplyAmount));

        MockERC20(currency).transferFrom(msg.sender, address(this), supplyAmount);

        poolManager.lock(orders, callbackData);
    }

    function lockAquired(
        IPoolManager.SignedOrder memory order
    ) external {
        SupplySignedOrder memory supplyOrder = abi.decode(order.data, (SupplySignedOrder));

        poolManager.supply(supplyOrder.currency, supplyOrder.supplyAmount);
    }

    function settleCallback(
        bytes memory callbackData
    ) public {
        SupplySignedOrder memory supplyOrder = abi.decode(callbackData, (SupplySignedOrder));

        MockERC20(supplyOrder.currency).transfer(address(poolManager), supplyOrder.supplyAmount);

        poolManager.settle(supplyOrder.currency);
    }
}


contract TradeHook {
    PoolManager public poolManager;

    struct TradeSignedOrder {
        address currency0;
        address currency1;
        int256 tradeAmount;
        int256 entryUpdate;
        uint256 limitPrice;
    }

    struct SettleCallbackParams {
        address currency0;
        address currency1;
        uint256 amount0;
        uint256 amount1;
    }

    constructor(
        PoolManager _poolManager
    ) {
        poolManager = _poolManager;
    }

    function trade(
        uint256 vaultId,
        TradeSignedOrder memory tradeOrder,
        bytes memory callbackData        
    ) external {
        IPoolManager.SignedOrder[] memory orders = new IPoolManager.SignedOrder[](1);

        orders[0] = IPoolManager.SignedOrder(
            vaultId,
            abi.encode(tradeOrder),
            0
        );
        poolManager.lock(orders, callbackData);
    }

    function lockAquired(
        IPoolManager.SignedOrder memory order
    ) external {
        TradeSignedOrder memory tradeOrder = abi.decode(order.data, (TradeSignedOrder));

        poolManager.updatePerpPosition(tradeOrder.currency0, tradeOrder.currency1, tradeOrder.tradeAmount, tradeOrder.entryUpdate);
    }

    function settleCallback(
        bytes memory callbackData
    ) public {
        SettleCallbackParams memory settleCallbackParams = abi.decode(callbackData, (SettleCallbackParams));

        poolManager.take(settleCallbackParams.currency1, address(this), settleCallbackParams.amount1);

        // TODO: swap

        MockERC20(settleCallbackParams.currency0).transfer(address(poolManager), settleCallbackParams.amount0);

        poolManager.settle(settleCallbackParams.currency0);
        poolManager.settle(settleCallbackParams.currency1);
    }
}

contract PoolManagerTest is Test {
    PoolManager public poolManager;
    MockERC20 currency0;
    MockERC20 currency1;
    SupplyHook supplyHook;
    TradeHook tradeHook;

    function setUp() public {
        currency0 = new MockERC20("currency0","currency0",18);

        currency1 = new MockERC20("currency1","currency1",18);

        currency0.mint(address(this), 1e10);
        currency1.mint(address(this), 1e10);

        poolManager = new PoolManager();
        supplyHook = new SupplyHook(poolManager);
        tradeHook = new TradeHook(poolManager);

        // TODO: swap
        currency0.transfer(address(tradeHook), 1000);
        currency1.transfer(address(tradeHook), 1000);
    }

    function testSupply() public {
        currency0.approve(address(supplyHook), 1000);
        currency1.approve(address(supplyHook), 1000);

        supplyHook.supply(address(currency0), 1000);
        supplyHook.supply(address(currency1), 1000);

        tradeHook.trade(
            1,
            TradeHook.TradeSignedOrder(
                address(currency0),
                address(currency1),
                100,
                -100,
                0
            ),
            abi.encode(
                TradeHook.SettleCallbackParams(
                    address(currency0),
                    address(currency1),
                    100,
                    100
                )
            )
        );

        // assertEq(a, 1);
    }
}
