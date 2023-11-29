// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IFillerMarket {
    error SignerIsNotVaultOwner();

    error CallerIsNotFiller();

    struct SignedOrder {
        bytes order;
        bytes sig;
    }
}
