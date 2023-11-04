// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

library ArrayLib {
    function toArray(uint256 n) internal pure returns (uint256[] memory arr) {
        arr = new uint[](1);
        arr[0] = n;
    }

    function toArray(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }
}
