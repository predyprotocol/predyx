// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IPredyPool {
    error LockedBy(address locker);

    error CurrencyNotSettled();

    error InvalidAmount();

    error InvalidPairId();

    error CallerIsNotVaultOwner();

    error VaultIsNotDanger();

    error SlippageTooLarge();

    struct TradeParams {
        uint256 pairId;
        uint256 vaultId;
        int256 tradeAmount;
        int256 tradeAmountSqrt;
        bytes extraData;
    }

    struct TradeResult {
        Payoff payoff;
        uint256 vaultId;
        int256 fee;
        int256 minDeposit;
        int256 averagePrice;
        uint160 sqrtTwap;
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

    function trade(TradeParams memory tradeParams, bytes memory settlementData)
        external
        returns (TradeResult memory tradeResult);
    function execLiquidationCall(uint256 vaultId, uint256 closeRatio, bytes memory settlementData)
        external
        returns (TradeResult memory tradeResult);

    function take(bool isQuoteAsset, address to, uint256 amount) external;

    function updateMargin(uint256 vaultId, int256 marginAmount) external;

    function getSqrtIndexPrice(uint256 pairId) external view returns (uint160);
}
