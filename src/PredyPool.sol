// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "./interfaces/IPredyPool.sol";
import "./interfaces/IHooks.sol";
import "./libraries/Perp.sol";
import "./libraries/logic/AddPairLogic.sol";
import "./libraries/logic/SupplyLogic.sol";
import "./libraries/logic/TradeLogic.sol";

contract PredyPool is IPredyPool, IUniswapV3MintCallback {
    GlobalDataLibrary.GlobalData public globalData;

    mapping(address => bool) public allowedUniswapPools;

    mapping(address currency => uint256) public reservesOf;

    mapping(address currency => int256 currencyDelta) public currencyDelta;

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
        // require(allowedUniswapPools[msg.sender]);
        IUniswapV3Pool uniswapPool = IUniswapV3Pool(msg.sender);
        if (amount0 > 0) {
            TransferHelper.safeTransfer(uniswapPool.token0(), msg.sender, amount0);
        }
        if (amount1 > 0) {
            TransferHelper.safeTransfer(uniswapPool.token1(), msg.sender, amount1);
        }
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
        return TradeLogic.trade(globalData, pairId, tradeParams, settlementData);
    }

    function execLiquidationCall(uint256 vaultId, uint256 closeRatio, bytes memory settlementData) external {}

    function take(uint256 pairId, bool isQuoteAsset, address to, uint256 amount) external onlyByLocker {
        address currency;
        GlobalDataLibrary.LockData memory lockData = globalData.lockData;

        if (isQuoteAsset) {
            lockData.quoteDelta += int256(amount);
            currency = globalData.pairs[pairId].quotePool.token;
        } else {
            lockData.baseDelta += int256(amount);
            currency = globalData.pairs[pairId].basePool.token;
        }

        IERC20(currency).transfer(to, amount);
    }

    function settle(uint256 pairId, bool isQuoteAsset) external onlyByLocker returns (uint256 paid) {
        address currency;
        uint256 reservesBefore;

        if (isQuoteAsset) {
            currency = globalData.pairs[pairId].quotePool.token;
            reservesBefore = globalData.lockData.quoteReserve;
        } else {
            currency = globalData.pairs[pairId].basePool.token;
            reservesBefore = globalData.lockData.baseReserve;
        }

        uint256 reserveAfter = IERC20(currency).balanceOf(address(this));

        paid = reserveAfter - reservesBefore;

        if (isQuoteAsset) {
            globalData.lockData.quoteDelta -= int256(paid);
        } else {
            globalData.lockData.baseDelta -= int256(paid);
        }
    }

    function updateMargin(uint256 vaultId, int256 marginAmount) external onlyByLocker {}

    function getSqrtIndexPrice(uint256 pairId) external view returns (uint256) {}

    function getPairStatus(uint256 pairId) external view returns (Perp.PairStatus memory) {
        return globalData.pairs[pairId];
    }

    function getVaultStatus(uint256 vaultId) external view returns (VaultStatus memory) {}
}
