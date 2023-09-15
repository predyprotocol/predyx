// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Perp} from "../libraries/Perp.sol";

interface IPredyPool {
    error LockedBy(address locker);

    error CurrencyNotSettled();

    error InvalidAmount();

    error InvalidPairId();

    struct TradeParams {
        uint256 pairId;
        uint256 vaultId;
        int256 tradeAmount;
        int256 tradeAmountSqrt;
        bytes extraData;
    }

    struct TradeResult {
        Perp.Payoff payoff;
        int256 fee;
        int256 minDeposit;
    }

    struct VaultStatus {
        uint256 id;
        int256 margin;
    }

    function trade(uint256 pairId, TradeParams memory tradeParams, bytes memory settlementData)
        external
        returns (TradeResult memory tradeResult);

    function take(bool isQuoteAsset, address to, uint256 amount) external;
}
