// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IPredyPool} from "./interfaces/IPredyPool.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {IHooks} from "./interfaces/IHooks.sol";
import {ISettlement} from "./interfaces/ISettlement.sol";
import {Perp} from "./libraries/Perp.sol";
import {VaultLib} from "./libraries/VaultLib.sol";
import {PositionCalculator} from "./libraries/PositionCalculator.sol";
import {DataType} from "./libraries/DataType.sol";
import {UniHelper} from "./libraries/UniHelper.sol";
import {AddPairLogic} from "./libraries/logic/AddPairLogic.sol";
import {LiquidationLogic} from "./libraries/logic/LiquidationLogic.sol";
import {ReallocationLogic} from "./libraries/logic/ReallocationLogic.sol";
import {SupplyLogic} from "./libraries/logic/SupplyLogic.sol";
import {TradeLogic} from "./libraries/logic/TradeLogic.sol";
import {MarginLogic} from "./libraries/logic/MarginLogic.sol";
import {ReaderLogic} from "./libraries/logic/ReaderLogic.sol";
import {LockDataLibrary, GlobalDataLibrary} from "./types/GlobalData.sol";

/**
 * @notice Holds the state for all pairs and vaults
 */
contract PredyPool is IPredyPool, ILendingPool, IUniswapV3MintCallback {
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;
    using LockDataLibrary for LockDataLibrary.LockData;
    using VaultLib for GlobalDataLibrary.GlobalData;

    GlobalDataLibrary.GlobalData public globalData;

    mapping(address => bool) public allowedUniswapPools;

    mapping(address trader => mapping(uint256 pairId => bool)) public allowedTraders;

    event RecepientUpdated(uint256 vaultId, address recipient);

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
    function registerPair(AddPairLogic.AddPairParams memory addPairParam) external returns (uint256) {
        return AddPairLogic.addPair(globalData, allowedUniswapPools, addPairParam);
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
        globalData.validate(tradeParams.pairId);

        if (globalData.pairs[tradeParams.pairId].whitelistEnabled && !allowedTraders[msg.sender][tradeParams.pairId]) {
            revert TraderNotAllowed();
        }

        DataType.Vault storage vault = globalData.createOrGetVault(tradeParams.vaultId, tradeParams.pairId);

        tradeParams.vaultId = vault.id;

        return TradeLogic.trade(globalData, tradeParams, settlementData);
    }

    /**
     * @notice Updates margin recipient address for position liquidation
     * @param vaultId The id of the vault.
     * @param recipient if recipient is zero address, protocol never transfers margin.
     */
    function updateRecepient(uint256 vaultId, address recipient) external {
        DataType.Vault storage vault = globalData.getVault(vaultId);

        vault.recipient = recipient;

        emit RecepientUpdated(vaultId, recipient);
    }

    /**
     * @notice Add whitelist trader
     * @param pairId The id of pair
     * @param trader The address of allowed trader
     */
    function addWhitelistAddress(uint256 pairId, address trader) external {
        require(globalData.pairs[pairId].whitelistEnabled);
        require(globalData.pairs[pairId].poolOwner == msg.sender);

        allowedTraders[trader][pairId] = true;
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
        globalData.getVault(vaultId);

        MarginLogic.updateMargin(globalData, vaultId, marginAmount);
    }

    function createVault(uint256 pairId) external returns (uint256) {
        globalData.validate(pairId);

        DataType.Vault storage vault = globalData.createOrGetVault(0, pairId);

        return vault.id;
    }

    /// @notice Gets the square root of the AMM price
    function getSqrtPrice(uint256 pairId) external view returns (uint160) {
        return UniHelper.convertSqrtPrice(
            UniHelper.getSqrtPrice(globalData.pairs[pairId].sqrtAssetStatus.uniswapPool),
            globalData.pairs[pairId].isMarginZero
        );
    }

    /// @notice Gets the square root of the index price
    function getSqrtIndexPrice(uint256 pairId) external view returns (uint256) {
        return PositionCalculator.getSqrtIndexPrice(globalData.pairs[pairId]);
    }

    function getPositionWithUnrealizedFee(uint256 vaultId)
        external
        view
        returns (PositionCalculator.PositionParams memory)
    {
        return ReaderLogic.getPositionWithUnrealizedFee(globalData, vaultId);
    }

    /// @notice Gets the status of pair
    function getPairStatus(uint256 pairId) external view returns (Perp.PairStatus memory) {
        return globalData.pairs[pairId];
    }

    /// @notice Gets the vault
    function getVault(uint256 vaultId) external view returns (DataType.Vault memory) {
        return globalData.vaults[vaultId];
    }

    /// @notice Gets the status of the vault
    function getVaultStatus(uint256 vaultId) external view returns (VaultStatus memory) {
        uint256 pairId = globalData.vaults[vaultId].openPosition.pairId;

        (int256 minMargin, int256 vaultValue,,) = PositionCalculator.calculateMinDeposit(
            globalData.pairs[pairId], globalData.rebalanceFeeGrowthCache, globalData.vaults[vaultId]
        );

        return VaultStatus(vaultId, vaultValue, minMargin);
    }

    /// @notice Gets the status of pair
    /// @dev This function always reverts
    function revertPairStatus(uint256 pairId) external {
        ReaderLogic.getPairStatus(globalData, pairId);
    }

    /// @notice Gets the status of the vault
    /// @dev This function always reverts
    function revertVaultStatus(uint256 vaultId) external {
        ReaderLogic.getVaultStatus(globalData, vaultId);
    }
}
