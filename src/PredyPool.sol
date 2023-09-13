// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./interfaces/IPredyPool.sol";
import "./interfaces/IHooks.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract PredyPool is IPredyPool {
    IPredyPool.LockData public lockData;

    mapping(address currency => uint256) public reservesOf;

    mapping(address currency => int256 currencyDelta) public currencyDelta;

    uint256 pairCount;

    mapping(uint256 pairId => PairStatus) public pairs;

    modifier onlyByLocker() {
        address locker = lockData.locker;
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    function registerPair(address pool, address quoteToken, address baseToken) external {
        uint256 pairId = ++pairCount;
        pairs[pairId] = PairStatus(pairId, pool, quoteToken, baseToken);
    }

    function supply(uint256 pairId, bool isQuoteAsset, uint256 supplyAmount, uint256 maxSupplyAmount) external returns (uint256 finalSuppliedAmount){
        /*
        IERC20(isQuoteAsset?pairs[pairId].quoteAsset:pairs[pairId].baseAsset).transferFrom(
            msg.sender,
            address(this),
            supplyAmount
        );

        saveReserveOf(pairs[pairId].baseAsset);
        saveReserveOf(pairs[pairId].quoteAsset);
        */
    }

    function withdraw(uint256 pairId, bool isQuoteAsset, uint256 withdrawAmount, uint256 minWithdrawAmount) external returns (uint256 finalWithdrawnAmount) {
    }

    function reallocate(uint256 pairId) external {
    }

    function trade(uint256 pairId, TradeParams memory tradeParams, bytes memory settlementData) external returns (TradeResult memory tradeResult) {
    }

    function execLiquidationCall(uint256 vaultId, uint256 closeRatio, bytes memory settlementData) external {
    }

    function take(uint256 pairId, bool isQuoteAsset, address to, uint256 amount) external onlyByLocker {
    }

    function settle(uint256 pairId, bool isQuoteAsset) external onlyByLocker {
    }

    function updateMargin(uint256 vaultId, int256 marginAmount) external onlyByLocker {
    }

    function getSqrtIndexPrice(uint256 pairId) external view returns (uint256) {
    }

    function getPairStatus(uint256 pairId) external view returns (PairStatus memory) {
    }

    function getVaultStatus(uint256 vaultId) external view returns (VaultStatus memory) {
    }
}
