// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import "../interfaces/ILendingPool.sol";
import "../libraries/math/Math.sol";
import "./BaseSettlement.sol";

contract UniswapSettlement is BaseSettlement {
    using Math for uint256;
    using SafeTransferLib for ERC20;

    ISwapRouter private immutable _swapRouter;
    IQuoterV2 private immutable _quoterV2;
    address public immutable filler;

    struct SettlementParams {
        bytes path;
        uint256 amountOutMinimumOrInMaximum;
        address quoteTokenAddress;
        address baseTokenAddress;
        int256 fee;
    }

    constructor(ILendingPool predyPool, address swapRouterAddress, address quoterAddress, address _filler)
        BaseSettlement(predyPool)
    {
        _swapRouter = ISwapRouter(swapRouterAddress);

        _quoterV2 = IQuoterV2(quoterAddress);

        filler = _filler;
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
        if (address(_predyPool) != msg.sender) revert CallerIsNotLendingPool();

        // This is a settlement function using Uniswap Router
        // filler can set negative fee
        SettlementParams memory settlementParams = abi.decode(settlementData, (SettlementParams));

        if (settlementParams.fee < 0) {
            ERC20(settlementParams.quoteTokenAddress).safeTransferFrom(
                filler, address(this), uint256(-settlementParams.fee)
            );
        }

        if (baseAmountDelta > 0) {
            _predyPool.take(false, address(this), uint256(baseAmountDelta));

            ERC20(settlementParams.baseTokenAddress).approve(address(_swapRouter), uint256(baseAmountDelta));

            uint256 quoteAmount = _swapRouter.exactInput(
                ISwapRouter.ExactInputParams(
                    settlementParams.path,
                    address(this),
                    block.timestamp,
                    uint256(baseAmountDelta),
                    settlementParams.amountOutMinimumOrInMaximum
                )
            );

            ERC20(settlementParams.quoteTokenAddress).safeTransfer(
                address(_predyPool), quoteAmount.addDelta(-settlementParams.fee)
            );
        } else {
            _predyPool.take(true, address(this), settlementParams.amountOutMinimumOrInMaximum);

            ERC20(settlementParams.quoteTokenAddress).approve(
                address(_swapRouter), settlementParams.amountOutMinimumOrInMaximum
            );

            uint256 quoteAmount = _swapRouter.exactOutput(
                ISwapRouter.ExactOutputParams(
                    settlementParams.path,
                    address(_predyPool),
                    block.timestamp,
                    uint256(-baseAmountDelta),
                    settlementParams.amountOutMinimumOrInMaximum
                )
            );

            ERC20(settlementParams.quoteTokenAddress).safeTransfer(
                address(_predyPool),
                settlementParams.amountOutMinimumOrInMaximum - quoteAmount.addDelta(settlementParams.fee)
            );
        }

        // send fee to the filler
        if (settlementParams.fee > 0) {
            ERC20(settlementParams.quoteTokenAddress).safeTransfer(filler, uint256(settlementParams.fee));
        }
    }

    /// @notice Quote the amount of quote token to be settled
    /// @dev This function is not gas efficient and should not be called on chain.
    function quoteSettlement(bytes memory settlementData, int256 baseAmountDelta) external override {
        SettlementParams memory settlementParams = abi.decode(settlementData, (SettlementParams));

        int256 quoteAmount;

        if (baseAmountDelta > 0) {
            (uint256 quoteAmountOut,,,) = _quoterV2.quoteExactInput(settlementParams.path, uint256(baseAmountDelta));

            quoteAmount = int256(quoteAmountOut.addDelta(-settlementParams.fee));
        } else {
            (uint256 quoteAmountIn,,,) = _quoterV2.quoteExactOutput(settlementParams.path, uint256(-baseAmountDelta));

            quoteAmount = -int256(quoteAmountIn.addDelta(settlementParams.fee));
        }

        _revertQuoteAmount(quoteAmount);
    }
}
