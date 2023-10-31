// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface ILendingPool {
    function take(bool isQuoteAsset, address to, uint256 amount) external;
}
