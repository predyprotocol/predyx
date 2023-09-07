// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../interfaces/IExchange.sol";
import "../interfaces/IAssetHooks.sol";

abstract contract BaseAssetHooks {
    IExchange exchange;

    constructor(IExchange _exchange) {
        exchange = _exchange;
    }

    function compose(bytes memory data) external virtual;
}
