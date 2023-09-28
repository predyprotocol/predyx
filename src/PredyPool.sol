// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "./interfaces/IPredyPool.sol";
import "./interfaces/IHooks.sol";
import "./interfaces/ISettlement.sol";
import "./libraries/Perp.sol";
import "./libraries/logic/AddPairLogic.sol";
import "./libraries/logic/LiquidationLogic.sol";
import "./libraries/logic/ReallocationLogic.sol";
import "./libraries/logic/SupplyLogic.sol";
import "./libraries/logic/TradeLogic.sol";
import "./libraries/logic/MarginLogic.sol";
import {GlobalDataLibrary} from "./types/GlobalData.sol";

/**
 * @notice Holds the state for all pairs and vaults
 */
contract PredyPool is IPredyPool, IUniswapV3MintCallback {
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;
    using LockDataLibrary for LockDataLibrary.LockData;

    GlobalDataLibrary.GlobalData public globalData;

    mapping(address => bool) public allowedUniswapPools;

    modifier onlyByLocker() {
        address locker = globalData.lockData.locker;
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    constructor(address uniswapFactory) {
        globalData.uniswapFactory = uniswapFactory;
        AddPairLogic.initializeGlobalData(globalData);
    }

    /**
     * @dev Callback for Uniswap V3 pool.
     */
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata) external override {
        require(allowedUniswapPools[msg.sender]);
        IUniswapV3Pool uniswapPool = IUniswapV3Pool(msg.sender);
        if (amount0 > 0) {
            TransferHelper.safeTransfer(uniswapPool.token0(), msg.sender, amount0);
        }
        if (amount1 > 0) {
            TransferHelper.safeTransfer(uniswapPool.token1(), msg.sender, amount1);
        }
    }

    /**
     * @notice Adds a new trading pair.
     * @param addPairParam AddPairParams struct containing pair information.
     */
    function registerPair(AddPairLogic.AddPairParams memory addPairParam) external {
        AddPairLogic.addPair(globalData, allowedUniswapPools, addPairParam);
    }

    /**
     * @notice Supplies liquidity to the lending pool
     */
    function supply(uint256 pairId, bool isQuoteAsset, uint256 supplyAmount)
        external
        returns (uint256 finalSuppliedAmount)
    {
        return SupplyLogic.supply(globalData, pairId, supplyAmount, isQuoteAsset);
    }

    /**
     * @notice Withdraws liquidity from the lending pool
     */
    function withdraw(uint256 pairId, bool isQuoteAsset, uint256 withdrawAmount)
        external
        returns (uint256 finalBurnAmount, uint256 finalWithdrawAmount)
    {
        return SupplyLogic.withdraw(globalData, pairId, withdrawAmount, isQuoteAsset);
    }

    /**
     * @notice Reallocated the range of concentrated liquidity provider position
     */
    function reallocate(uint256 pairId, ISettlement.SettlementData memory settlementData)
        external
        returns (bool relocationOccurred)
    {
        return ReallocationLogic.reallocate(globalData, pairId, settlementData);
    }

    /**
     * @notice This function allows users to open or close perpetual future positions.
     * @param tradeParams trade details
     * @param settlementData byte data for settlement contract.
     * @return tradeResult The result of the trade.
     */
    function trade(TradeParams memory tradeParams, ISettlement.SettlementData memory settlementData)
        external
        returns (TradeResult memory tradeResult)
    {
        if (tradeParams.vaultId == 0) {
            tradeParams.vaultId = globalData.vaultCount;

            // Initialize a new vault
            DataType.Vault storage vault = globalData.vaults[tradeParams.vaultId];

            vault.owner = msg.sender;
            vault.recepient = msg.sender;
            vault.openPosition.pairId = tradeParams.pairId;

            globalData.vaultCount++;
        } else {
            DataType.Vault memory vault = globalData.vaults[tradeParams.vaultId];

            // Ensure the caller is the owner of the existing vault
            if (vault.owner != msg.sender) {
                revert CallerIsNotVaultOwner();
            }

            if (vault.openPosition.pairId != tradeParams.pairId) {
                revert VaultAlreadyHasAnotherPair();
            }
        }

        return TradeLogic.trade(globalData, tradeParams, settlementData);
    }

    function updateRecepient(uint256 vaultId, address recepient) external {
        DataType.Vault storage vault = globalData.vaults[vaultId];

        if (recepient == address(0)) {
            revert InvalidAddress();
        }

        if (vault.owner != msg.sender) {
            revert CallerIsNotVaultOwner();
        }

        vault.recepient = recepient;
    }

    /**
     * @notice Executes a liquidation call to close an unsafe vault.
     * @param vaultId The identifier of the vault to be liquidated.
     * @param closeRatio The ratio at which the position will be closed.
     * @param settlementData SettlementData struct for trade settlement.
     * @return tradeResult TradeResult struct with the result of the liquidation.
     */
    function execLiquidationCall(uint256 vaultId, uint256 closeRatio, ISettlement.SettlementData memory settlementData)
        external
        returns (TradeResult memory tradeResult)
    {
        return LiquidationLogic.liquidate(vaultId, closeRatio, globalData, settlementData);
    }

    /**
     * @notice Takes tokens
     * @dev Only locker can call this function
     */
    function take(bool isQuoteAsset, address to, uint256 amount) external onlyByLocker {
        globalData.take(isQuoteAsset, to, amount);
    }

    /**
     * @notice Deposits margin to the vault or withdraws margin from the vault
     * @dev Only locker can call this function
     */
    function updateMargin(uint256 vaultId, int256 marginAmount) external {
        DataType.Vault storage vault = globalData.vaults[vaultId];

        MarginLogic.updateMargin(
            vault, globalData.pairs[vault.openPosition.pairId], globalData.rebalanceFeeGrowthCache, marginAmount
        );
    }

    function getSqrtPrice(uint256 pairId) external view returns (uint160) {
        return UniHelper.convertSqrtPrice(
            UniHelper.getSqrtPrice(globalData.pairs[pairId].sqrtAssetStatus.uniswapPool),
            globalData.pairs[pairId].isMarginZero
        );
    }

    function getSqrtIndexPrice(uint256 pairId) external view returns (uint160) {
        return UniHelper.convertSqrtPrice(
            UniHelper.getSqrtTWAP(globalData.pairs[pairId].sqrtAssetStatus.uniswapPool),
            globalData.pairs[pairId].isMarginZero
        );
    }

    function getPairStatus(uint256 pairId) external view returns (Perp.PairStatus memory) {
        return globalData.pairs[pairId];
    }

    function getVault(uint256 vaultId) external view returns (DataType.Vault memory) {
        return globalData.vaults[vaultId];
    }

    function getVaultStatus(uint256 vaultId) external view returns (VaultStatus memory) {}
}
