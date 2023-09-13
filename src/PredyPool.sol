// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./interfaces/IPredyPool.sol";
import "./interfaces/IHooks.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

import "./libraries/Perp.sol";
import "./libraries/logic/AddPairLogic.sol";
import "./libraries/logic/SupplyLogic.sol";
import "./libraries/logic/TradeLogic.sol";


contract PredyPool is IPredyPool {
    GlobalDataLibrary.GlobalData public globalData;

    IPredyPool.LockData public lockData;

    mapping(address => bool) public allowedUniswapPools;

    mapping(address currency => uint256) public reservesOf;

    mapping(address currency => int256 currencyDelta) public currencyDelta;

    modifier onlyByLocker() {
        address locker = lockData.locker;
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    constructor(address uniswapFactory) {
        globalData.uniswapFactory = uniswapFactory;
        AddPairLogic.initializeGlobalData(globalData);
    }

    function registerPair(AddPairLogic.AddPairParams memory addPairParam) external {
        AddPairLogic.addPair(globalData, allowedUniswapPools, addPairParam);
    }

    function supply(uint256 pairId, bool isQuoteAsset, uint256 supplyAmount)
        external
        returns (uint256 finalSuppliedAmount)
    {
        return SupplyLogic.supply(globalData, pairId, supplyAmount, isQuoteAsset);
    }

    function withdraw(uint256 pairId, bool isQuoteAsset, uint256 withdrawAmount)
        external
        returns (uint256 finalBurnAmount, uint256 finalWithdrawAmount)
    {
        return SupplyLogic.withdraw(globalData, pairId, withdrawAmount, isQuoteAsset);
    }

    function reallocate(uint256 pairId) external {}

    function trade(uint256 pairId, TradeParams memory tradeParams, bytes memory settlementData)
        external
        returns (TradeResult memory tradeResult)
    {
        return TradeLogic.trade(
            globalData, pairId, tradeParams, settlementData
        );
    }

    function execLiquidationCall(uint256 vaultId, uint256 closeRatio, bytes memory settlementData) external {}

    function take(uint256 pairId, bool isQuoteAsset, address to, uint256 amount) external onlyByLocker {}

    function settle(uint256 pairId, bool isQuoteAsset) external onlyByLocker {}

    function updateMargin(uint256 vaultId, int256 marginAmount) external onlyByLocker {}

    function getSqrtIndexPrice(uint256 pairId) external view returns (uint256) {}

    function getPairStatus(uint256 pairId) external view returns (Perp.PairStatus memory) {
        return globalData.pairs[pairId];
    }

    function getVaultStatus(uint256 vaultId) external view returns (VaultStatus memory) {}
}
