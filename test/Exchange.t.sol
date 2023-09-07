// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "../src/Exchange.sol";
import "../src/assets/PerpAssetHooks.sol";
import "../src/assets/LendingAssetHooks.sol";
import "../src/settlements/SettlementHooks.sol";
import "../src/settlements/DepositSettlementHooks.sol";

contract ExchangeTest is Test {
    Exchange public exchange;
    PerpAssetHooks perpAssetHooks;
    LendingAssetHooks lendingAssetHooks;
    SettlementHooks settlementHook;
    DepositSettlementHooks depositSettlementHook;
    MockERC20 currency0;
    MockERC20 currency1;

    function setUp() public {
        currency0 = new MockERC20("currency0","currency0",18);

        currency1 = new MockERC20("currency1","currency1",18);

        currency0.mint(address(this), 1e10);
        currency1.mint(address(this), 1e10);

        exchange = new Exchange();
        exchange.registerPair(
            address(0), address(currency1), address(currency0)
        );

        perpAssetHooks = new PerpAssetHooks(exchange);
        lendingAssetHooks = new LendingAssetHooks(exchange);
        settlementHook = new SettlementHooks(exchange);
        depositSettlementHook = new DepositSettlementHooks(exchange);

        currency0.transfer(address(settlementHook), 1000);
        currency1.transfer(address(settlementHook), 1000);
        currency0.transfer(address(depositSettlementHook), 1000);
        currency1.transfer(address(depositSettlementHook), 1000);

        supply(false, 500);
        supply(true, 500);
    }

    function supply(bool isQuoteAsset, uint256 supplyAmount) public {
        bytes memory data = abi.encode(
            LendingAssetHooks.LendingAssetComposeParams(1, isQuoteAsset, supplyAmount)
        );

        bytes memory callbackData = abi.encode(
            DepositSettlementHooks.SettleCallbackParams(
                1, isQuoteAsset, address(isQuoteAsset ? currency1 : currency0)
            )
        );

        exchange.trade(
            1,
            address(lendingAssetHooks),
            address(depositSettlementHook),
            data,
            callbackData
        );
    }

    function testTradeSucceeds() public {
        uint256 pairId = 1;
        bytes memory data =
            abi.encode(PerpAssetHooks.PerpAssetComposeParams(pairId, 100, 1e18));

        bytes memory callbackData = abi.encode(
            SettlementHooks.SettleCallbackParams(
                pairId, address(currency0), address(currency1)
            )
        );

        exchange.trade(
            pairId,
            address(perpAssetHooks),
            address(settlementHook),
            data,
            callbackData
        );
    }
}
