// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ILendingPool.sol";
import "../libraries/math/Math.sol";
import "./BaseSettlement.sol";

contract UniswapSettlement is BaseSettlement {
    using Math for uint256;

    ISwapRouter _swapRouter;

    struct SettlementParams {
        bytes path;
        uint256 amountOutMinimumOrInMaximum;
        address quoteTokenAddress;
        address baseTokenAddress;
        int256 fee;
    }

    constructor(ILendingPool _predyPool, address swapRouterAddress) BaseSettlement(_predyPool) {
        _swapRouter = ISwapRouter(swapRouterAddress);
    }

    function getSettlementParams(
        bytes memory path,
        uint256 amountOutMinimumOrInMaximum,
        address quoteTokenAddress,
        address baseTokenAddress,
        int256 fee
    ) external view returns (ISettlement.SettlementData memory) {
        return ISettlement.SettlementData(
            address(this),
            abi.encode(SettlementParams(path, amountOutMinimumOrInMaximum, quoteTokenAddress, baseTokenAddress, fee))
        );
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta)
        external
        override(BaseSettlement)
    {
        require(address(_predyPool) == msg.sender);
        // This is a settlement function using Uniswap Router
        // filler can set negative fee
        SettlementParams memory settlementParams = abi.decode(settlementData, (SettlementParams));

        if (baseAmountDelta > 0) {
            _predyPool.take(false, address(this), uint256(baseAmountDelta));

            IERC20(settlementParams.baseTokenAddress).approve(address(_swapRouter), uint256(baseAmountDelta));

            uint256 quoteAmount = _swapRouter.exactInput(
                ISwapRouter.ExactInputParams(
                    settlementParams.path,
                    address(this),
                    block.timestamp,
                    uint256(baseAmountDelta),
                    settlementParams.amountOutMinimumOrInMaximum
                )
            );

            TransferHelper.safeTransfer(
                settlementParams.quoteTokenAddress, address(_predyPool), quoteAmount.addDelta(-settlementParams.fee)
            );
        } else {
            IERC20(settlementParams.quoteTokenAddress).approve(
                address(_swapRouter), settlementParams.amountOutMinimumOrInMaximum
            );

            _predyPool.take(true, address(this), settlementParams.amountOutMinimumOrInMaximum);

            uint256 quoteAmount = _swapRouter.exactOutput(
                ISwapRouter.ExactOutputParams(
                    settlementParams.path,
                    address(_predyPool),
                    block.timestamp,
                    uint256(-baseAmountDelta),
                    settlementParams.amountOutMinimumOrInMaximum
                )
            );

            TransferHelper.safeTransfer(
                settlementParams.quoteTokenAddress,
                address(_predyPool),
                settlementParams.amountOutMinimumOrInMaximum - quoteAmount.addDelta(-settlementParams.fee)
            );
        }
    }
}
