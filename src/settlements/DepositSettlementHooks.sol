// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./BaseSettlementHooks.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DepositSettlementHooks is BaseSettlementHooks {
    struct SettleCallbackParams {
        uint256 pairId;
        bool isQuoteAsset;
        address currency;
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

        int256 settleAmount =
            settleCallbackParams.isQuoteAsset ? quoteAmountDelta : baseAmountDelta;

        if (settleAmount > 0) {
            IERC20(settleCallbackParams.currency).transfer(
                address(exchange), uint256(settleAmount)
            );

            exchange.settle(
                settleCallbackParams.pairId, settleCallbackParams.isQuoteAsset
            );
        }
    }
}
