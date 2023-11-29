// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {ISettlement} from "./ISettlement.sol";
import {DataType} from "../libraries/DataType.sol";

interface IPredyPool {
    error CallerIsNotOperator();

    error CallerIsNotPoolCreator();

    error LockedBy(address locker);

    error CurrencyNotSettled();

    error InvalidAmount();

    error InvalidPairId();

    error InvalidAddress();

    error VaultIsNotDanger();

    error TraderNotAllowed();

    // VaultLib
    error VaultAlreadyHasAnotherPair();

    error VaultAlreadyHasAnotherMarginId();

    error CallerIsNotVaultOwner();

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
        int256 minMargin;
        int256 averagePrice;
        uint256 sqrtTwap;
        uint256 sqrtPrice;
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
        int256 vaultValue;
        int256 minMargin;
    }

    function trade(TradeParams memory tradeParams, ISettlement.SettlementData memory settlementData)
        external
        returns (TradeResult memory tradeResult);
    function execLiquidationCall(uint256 vaultId, uint256 closeRatio, ISettlement.SettlementData memory settlementData)
        external
        returns (TradeResult memory tradeResult);

    function updateRecepient(uint256 vaultId, address recipient) external;

    function updateMargin(uint256 vaultId, int256 marginAmount) external;
    function createVault(uint256 pairId) external returns (uint256);

    function getSqrtPrice(uint256 pairId) external view returns (uint160);

    function getSqrtIndexPrice(uint256 pairId) external view returns (uint256);

    function getVault(uint256 vaultId) external view returns (DataType.Vault memory);
    function getVaultStatus(uint256 vaultId) external view returns (VaultStatus memory);
    function getPairStatus(uint256 pairId) external view returns (DataType.PairStatus memory);

    function revertPairStatus(uint256 pairId) external;
    function revertVaultStatus(uint256 vaultId) external;
}
