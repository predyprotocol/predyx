// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./BaseAssetHooks.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PerpAssetHooks is BaseAssetHooks {
    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    struct PerpAssetComposeParams {
        uint256 pairId;
        int256 tradeAmount;
        int256 limitPrice;
    }

    constructor(IExchange _exchange) BaseAssetHooks(_exchange) {}

    // compose and decompose
    function compose(bytes memory data) external override {
        PerpAssetComposeParams memory order =
            abi.decode(data, (PerpAssetComposeParams));

        exchange.updatePosition(order.pairId, false, order.tradeAmount);
    }

    function addDebt(bytes memory data, int256 averagePrice) external {
        PerpAssetComposeParams memory order =
            abi.decode(data, (PerpAssetComposeParams));

        int256 entryUpdate = -averagePrice * order.tradeAmount / 1e18;

        // TODO: updatePosition
        exchange.updatePosition(order.pairId, true, entryUpdate);

        if (order.tradeAmount > 0 && order.limitPrice < averagePrice) {
            revert PriceGreaterThanLimit();
        } else if (order.tradeAmount < 0 && order.limitPrice > averagePrice) {
            revert PriceLessThanLimit();
        }
    }
}
