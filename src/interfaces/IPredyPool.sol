// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IPredyPool {
    error LockedBy(address locker);

    error CurrencyNotSettled();

    error InvalidAmount();

    error InvalidPairId();

    struct LockData {
        address locker;
        uint256 deltaCount;
        uint256 pairId;
        uint256 vaultId;
    }

    struct TradeParams {
        uint256 pairId;
        uint256 vaultId;
        int256 tradeAmount;
        int256 tradeAmountSqrt;
        bytes extraData;
    }

    struct TradeResult {
        Payoff payoff;
        int256 fee;
        int256 minDeposit;
    }

    struct Payoff {
        int256 perpEntryUpdate;
        int256 sqrtEntryUpdate;
        int256 sqrtRebalanceEntryUpdateUnderlying;
        int256 sqrtRebalanceEntryUpdateStable;
        int256 perpPayoff;
        int256 sqrtPayoff;
    }

    struct VaultStatus {
        uint256 id;
        int256 margin;
    }
}
