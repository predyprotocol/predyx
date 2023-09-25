// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0;

interface ISettlement {
    struct SettlementData {
        address settlementContractAddress;
        bytes encodedData;
    }

    function predySettlementCallback(bytes memory settlementData, int256 baseAmountDelta) external;
}
