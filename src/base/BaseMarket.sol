// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Owned} from "@solmate/src/auth/Owned.sol";
import "./BaseHookCallback.sol";

abstract contract BaseMarket is BaseHookCallback, Owned {
    address public _whitelistFiller;

    constructor(IPredyPool predyPool, address whitelistFiller) BaseHookCallback(predyPool) Owned(msg.sender) {
        _whitelistFiller = whitelistFiller;
    }

    function updateWhitelistFiller(address newWhitelistFiller) external onlyOwner {
        _whitelistFiller = newWhitelistFiller;
    }
}
