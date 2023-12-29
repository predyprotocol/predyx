// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "../interfaces/ISettlement.sol";

abstract contract BaseSettlement is ISettlement {
    error CallerIsNotLendingPool();

    constructor() {}

    function swapExactIn(
        address quoteToken,
        address baseToken,
        bytes memory data,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient
    ) external virtual returns (uint256 amountOut);

    function swapExactOut(
        address quoteToken,
        address baseToken,
        bytes memory data,
        uint256 amountOut,
        uint256 amountInMaximum,
        address recipient
    ) external virtual returns (uint256 amountIn);

    function quoteSwapExactIn(bytes memory data, uint256 amountIn) external virtual returns (uint256 amountOut);

    function quoteSwapExactOut(bytes memory data, uint256 amountOut) external virtual returns (uint256 amountIn);
}
