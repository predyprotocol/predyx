// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./interfaces/IExchange.sol";
import "./interfaces/IAssetHooks.sol";
import "./interfaces/ISettlementHooks.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract Exchange is IExchange {
    IExchange.LockData public lockData;

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

    function trade(
        uint256 pairId,
        address _asset,
        address _settlementHook,
        bytes memory data,
        bytes memory settlementCallbackData
    ) external {
        lockData.pairId = pairId;

        lockData.locker = _asset;
        // compose asset
        IAssetHooks(_asset).compose(data);

        lockData.locker = _settlementHook;

        // settlement
        // filler choose an executor
        int256 averagePrice;

        {
            int256 quoteAmountDelta = currencyDelta[pairs[lockData.pairId].quoteAsset];
            int256 baseAmountDelta = currencyDelta[pairs[lockData.pairId].baseAsset];

            ISettlementHooks(_settlementHook).settlementCallback(
                settlementCallbackData, quoteAmountDelta, baseAmountDelta
            );

            if (baseAmountDelta != 0) {
                averagePrice = currencyDelta[pairs[lockData.pairId].quoteAsset] * 1e18 / baseAmountDelta;
            }
        }
        lockData.locker = _asset;

        // add debt
        IAssetHooks(_asset).addDebt(data, averagePrice);

        lockData.locker = address(0);

        if (lockData.deltaCount != 0) revert CurrencyNotSettled();

        saveReserveOf(pairs[lockData.pairId].baseAsset);
        saveReserveOf(pairs[lockData.pairId].quoteAsset);
    }

    function saveReserveOf(address currency) internal {
        reservesOf[currency] = IERC20(currency).balanceOf(address(this));
    }

    function liquidate() external {}

    function startAuction() external {}

    function take(bool isQuoteAsset, address to, uint256 amount) public onlyByLocker {
        updateAccountDelta(lockData.pairId, isQuoteAsset, int256(amount));

        address currency;

        if (isQuoteAsset) {
            currency = pairs[lockData.pairId].quoteAsset;
        } else {
            currency = pairs[lockData.pairId].baseAsset;
        }
        IERC20(currency).transfer(to, amount);
    }

    function settle(uint256 pairId, bool isQuoteAsset) public onlyByLocker returns (uint256 paid) {
        address currency;

        if (isQuoteAsset) {
            currency = pairs[pairId].quoteAsset;
        } else {
            currency = pairs[pairId].baseAsset;
        }

        uint256 reservesBefore = reservesOf[currency];

        uint256 reserveAfter = IERC20(currency).balanceOf(address(this));

        paid = reserveAfter - reservesBefore;

        reservesOf[currency] = reserveAfter;

        updateAccountDelta(pairId, isQuoteAsset, -int256(paid));
    }

    function updatePosition(uint256 pairId, bool isQuoteAsset, int256 delta) external onlyByLocker {
        // TODO: add asset or debt
        updateAccountDelta(pairId, isQuoteAsset, delta);
    }

    function updateAccountDelta(uint256 pairId, bool isQuoteAsset, int256 delta) internal {
        if (delta == 0) return;

        address currency;

        if (isQuoteAsset) {
            currency = pairs[pairId].quoteAsset;
        } else {
            currency = pairs[pairId].baseAsset;
        }

        address locker = lockData.locker;
        int256 current = currencyDelta[currency];
        int256 next = current + delta;

        // TODO: minus is valid

        if (next == 0) {
            lockData.deltaCount--;
        } else if (current == 0) {
            lockData.deltaCount++;
        }

        currencyDelta[currency] = next;
    }
}


