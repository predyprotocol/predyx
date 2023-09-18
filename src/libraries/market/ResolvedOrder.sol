// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {OrderInfo} from "./OrderInfoLib.sol";

struct ResolvedOrder {
    OrderInfo info;
    address token;
    uint256 amount;
    bytes32 hash;
    bytes sig;
}
