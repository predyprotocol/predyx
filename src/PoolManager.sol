// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./interfaces/IPoolManager.sol";
import "./interfaces/IHooks.sol";
import "./interfaces/IExecutor.sol";
import "./libraries/Math.sol";
import "forge-std/console.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external;

    function transferFrom(address from, address to, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);
}

contract PoolManager is IPoolManager {
    struct PairStatus {
        uint256 id;
        address pool;
        PoolStatus quoteAsset;
        PoolStatus baseAsset;
    }

    struct PoolStatus {
        address tokenAddress;
    }

    struct Vault {
        uint256 id;
        address marginId;
        uint256 margin;
    }

    mapping(address => mapping(uint256 => uint256)) public nonceBitmap;

    mapping(address currency => uint256) public reservesOf;

    mapping(address locker => mapping(address currency => int256 currencyDelta)) public currencyDelta;

    IPoolManager.LockData public lockData;

    uint256 pairCount;

    mapping(uint256 pairId => PairStatus) public pairs;

    mapping(uint256 vaultId => Vault) public vaults;

    modifier onlyByLocker() {
        address locker = lockData.locker;
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    constructor() {}

    function registerPair(address pool, address quoteToken, address baseToken) external {
        uint256 pairId = ++pairCount;
        pairs[pairId] = PairStatus(pairId, pool, PoolStatus(quoteToken), PoolStatus(baseToken));
    }

    function lockForSupply(bytes memory callbackData) external {
        lockData.locker = msg.sender;

        ISupplyHook(msg.sender).lockAquired(callbackData);

        lockData.locker = address(0);

        if (lockData.deltaCount != 0) revert CurrencyNotSettled();
    }

    function lockForTrade(uint256 pairId, IPoolManager.SignedOrder[] memory orders, bytes memory callbackData)
        external
    {
        // TODO: push lock
        lockData.locker = msg.sender;
        if (pairId <= 0 || pairId > pairCount) revert PairNotFound();
        lockData.pairId = pairId;

        // TODO: trade context

        for (uint256 i; i < orders.length; i++) {
            // TODO: check signature and nonce
            // TODO: create nonce management contract?

            // TODO: ここではpre trade処理をする
            prepareTradePerpPosition(orders[i]);
        }

        // unlock vault
        lockData.vaultId = 0;

        // filler choose an executor
        int256 averagePrice = currencyDelta[lockData.locker][pairs[lockData.pairId].baseAsset.tokenAddress];
        // TODO: take and settle
        IExecutor(msg.sender).settleCallback(callbackData, averagePrice);
        if (averagePrice != 0) {
            averagePrice =
                currencyDelta[lockData.locker][pairs[lockData.pairId].quoteAsset.tokenAddress] * 1e18 / averagePrice;
        }

        // fill
        for (uint256 i; i < orders.length; i++) {
            postTradePerpPosition(orders[i], averagePrice);

            // TODO:ここで自由にかけるpost trade
            lockData.vaultId = orders[i].vaultId;

            IHooks(msg.sender).afterTrade(orders[i]);
        }

        // TODO: pop lock data
        lockData.locker = address(0);

        if (lockData.deltaCount != 0) revert CurrencyNotSettled();

        for (uint256 i; i < orders.length; i++) {
            uint256 vaultId = orders[i].vaultId;

            validate(vaultId);
        }

        saveReserveOf(pairs[lockData.pairId].baseAsset.tokenAddress);
        saveReserveOf(pairs[lockData.pairId].quoteAsset.tokenAddress);
    }

    function saveReserveOf(address currency) internal {
        reservesOf[currency] = IERC20(currency).balanceOf(address(this));
    }

    function prepareTradePerpPosition(IPoolManager.SignedOrder memory order) public onlyByLocker {
        // TODO: updatePosition
        updateAccountDelta(order.pairId, false, order.tradeAmount);
        // updateAccountDelta(true, entryUpdate);
    }

    function postTradePerpPosition(IPoolManager.SignedOrder memory order, int256 averagePrice) public onlyByLocker {
        // quote amount for perp
        int256 entryUpdate = -averagePrice * order.tradeAmount / 1e18;
        // TODO: quote amount for sqrt perp
        // TODO: quote amount for premium

        // TODO: updatePosition
        updateAccountDelta(order.pairId, true, entryUpdate);

        if (order.tradeAmount > 0 && order.limitPrice < averagePrice) {
            revert PriceGreaterThanLimit();
        } else if (order.tradeAmount < 0 && order.limitPrice > averagePrice) {
            revert PriceLessThanLimit();
        }
    }

    function updateSqrtPerpPosition(uint256 vaultId, int256 tradeAmount, int256 entryUpdate) public onlyByLocker {
        require(vaultId == lockData.vaultId);

        // TODO: updatePosition
    }

    function updateMargin(uint256 vaultId, int256 marginAmount) public onlyByLocker {
        require(vaultId == lockData.vaultId);

        Vault storage vault = vaults[vaultId];

        vault.margin = Math.addDelta(vault.margin, marginAmount);

        // TODO: updatePosition
        updateAccountDelta(lockData.pairId, true, marginAmount);
    }

    function take(bool isQuoteAsset, address to, uint256 amount) public onlyByLocker {
        updateAccountDelta(lockData.pairId, isQuoteAsset, int256(amount));

        address currency;

        if (isQuoteAsset) {
            currency = pairs[lockData.pairId].quoteAsset.tokenAddress;
        } else {
            currency = pairs[lockData.pairId].baseAsset.tokenAddress;
        }
        IERC20(currency).transfer(to, amount);
    }

    function settle(uint256 pairId, bool isQuoteAsset) public onlyByLocker returns (uint256 paid) {
        address currency;

        if (isQuoteAsset) {
            currency = pairs[pairId].quoteAsset.tokenAddress;
        } else {
            currency = pairs[pairId].baseAsset.tokenAddress;
        }

        uint256 reservesBefore = reservesOf[currency];

        uint256 reserveAfter = IERC20(currency).balanceOf(address(this));

        paid = reserveAfter - reservesBefore;

        reservesOf[currency] = reserveAfter;

        updateAccountDelta(pairId, isQuoteAsset, -int256(paid));
    }

    function supply(uint256 pairId, bool isQuoteAsset, uint256 amount) public onlyByLocker {
        if (pairId <= 0 || pairId > pairCount) revert PairNotFound();

        updateAccountDelta(pairId, isQuoteAsset, int256(amount));
    }

    function withdraw(uint256 pairId, bool isQuoteAsset, uint256 amount) public onlyByLocker {
        if (pairId <= 0 || pairId > pairCount) revert PairNotFound();

        updateAccountDelta(pairId, isQuoteAsset, -int256(amount));
    }

    function validate(uint256 _vaultId) internal view {
        // custom validation
    }

    function updateAccountDelta(uint256 pairId, bool isQuoteAsset, int256 delta) internal {
        if (delta == 0) return;

        address currency;

        if (isQuoteAsset) {
            currency = pairs[pairId].quoteAsset.tokenAddress;
        } else {
            currency = pairs[pairId].baseAsset.tokenAddress;
        }

        address locker = lockData.locker;
        int256 current = currencyDelta[locker][currency];
        int256 next = current + delta;

        // TODO: minus is valid

        if (next == 0) {
            lockData.deltaCount--;
        } else if (current == 0) {
            lockData.deltaCount++;
        }

        currencyDelta[locker][currency] = next;
    }
}

contract PredyXHook {
    constructor() {}

    function lockAquired(IPoolManager.SignedOrder memory order) public {
        lockAquiredTrade(order);
    }

    function settleCallback(bytes memory callbackData) public {}

    function lockAquiredTrade(IPoolManager.SignedOrder memory order) internal {
        /*
        for(uint256 i;i < orders.length;i++) {
            controller.updatePerpPosition();
            controller.updateSqrtPosition();
        }

        swap();
        // ここでlimit orderで手に入れたトークンを使っても良い。

        controller.take();
        controller.settle();
        */
    }

    /*
    function tradeBatch(
        bytes[] memory orders
    ) public {
        controller.lock(orders);
    }
    */
}
