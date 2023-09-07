// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./BaseAssetHooks.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LendingAssetHooks is BaseAssetHooks {
    struct LendingAssetComposeParams {
        uint256 pairId;
        bool isQuoterAsset;
        uint256 supplyAmount;
    }

    constructor(IExchange _exchange) BaseAssetHooks(_exchange) {}

    // compose and decompose
    function compose(bytes memory data) external override {
        LendingAssetComposeParams memory order =
            abi.decode(data, (LendingAssetComposeParams));

        exchange.updatePosition(
            order.pairId, order.isQuoterAsset, int256(order.supplyAmount)
        );
    }

    function addDebt(bytes memory data, int256 averagePrice) external {}
}
