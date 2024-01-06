// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IFillerMarket {
    error SignerIsNotVaultOwner();

    error CallerIsNotFiller();

    struct SignedOrder {
        bytes order;
        bytes sig;
    }

    struct SettlementParams {
        uint256 price;
        int256 fee;
        SettlementParamsItem[] items;
    }

    struct SettlementParamsItem {
        address contractAddress;
        bytes encodedData;
        uint256 maxQuoteAmount;
        uint256 partialBaseAmount;
    }
}
