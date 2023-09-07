// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./BaseSettlementHooks.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SettlementHooks is BaseSettlementHooks {
    struct SettleCallbackParams {
        uint256 pairId;
        address currency0;
        address currency1;
    }

    constructor(IExchange _exchange) BaseSettlementHooks(_exchange) {}

    function settlementCallback(
        bytes memory callbackData,
        int256 quoteAmountDelta,
        int256 baseAmountDelta
    )
        public
        override
    {
        SettleCallbackParams memory settleCallbackParams =
            abi.decode(callbackData, (SettleCallbackParams));

        if (baseAmountDelta > 0) {
            uint256 settleAmount = uint256(baseAmountDelta);

            uint256 takeAmount = settleAmount;

            exchange.take(true, address(this), takeAmount);

            IERC20(settleCallbackParams.currency0).transfer(
                address(exchange), settleAmount
            );

            exchange.settle(settleCallbackParams.pairId, false);
        } else {
            uint256 takeAmount = uint256(-baseAmountDelta);

            uint256 settleAmount = takeAmount;

            exchange.take(false, address(this), takeAmount);

            IERC20(settleCallbackParams.currency1).transfer(
                address(exchange), settleAmount
            );

            exchange.settle(settleCallbackParams.pairId, true);
        }
    }
}
