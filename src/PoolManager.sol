// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./interfaces/IPoolManager.sol";
import "./interfaces/IHook.sol";
import "./interfaces/IExecutor.sol";
import "./libraries/Math.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external;

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

    function lock(uint256 pairId, IPoolManager.SignedOrder[] memory orders, bytes memory callbackData) external {
        // TODO: push lock
        lockData.locker = msg.sender;
        lockData.pairId = pairId;
        lockData.baseReserveBefore = IERC20(pairs[lockData.pairId].baseAsset.tokenAddress).balanceOf(address(this));
        lockData.quoteReserveBefore = IERC20(pairs[lockData.pairId].quoteAsset.tokenAddress).balanceOf(address(this));

        for (uint256 i; i < orders.length; i++) {
            // TODO: check signature and nonce
            // TODO: create nonce management contract?
            lockData.vaultId = orders[i].vaultId;

            // TODO: call lock aquired
            // trader choose a hook
            IHook(msg.sender).lockAquired(orders[i]);
        }

        // unlock vault
        lockData.vaultId = 0;

        // filler choose an ececutor
        IExecutor(msg.sender).settleCallback(callbackData, lockData);

        // fill
        for (uint256 i; i < orders.length; i++) {
            lockData.vaultId = orders[i].vaultId;

            IHook(msg.sender).postLockAquired(orders[i], lockData);
        }

        // TODO: pop lock data
        lockData.locker = address(0);

        if (lockData.deltaCount != 0) revert CurrencyNotSettled();

        for (uint256 i; i < orders.length; i++) {
            uint256 vaultId = orders[i].vaultId;

            validate(vaultId);
        }
    }

    function prepareTradePerpPosition(uint256 vaultId, int256 tradeAmount) public onlyByLocker {
        require(vaultId == lockData.vaultId);

        // TODO: updatePosition
        updateAccountDelta(false, tradeAmount);
        // updateAccountDelta(true, entryUpdate);
    }

    function postTradePerpPosition(uint256 vaultId, int256 entryUpdate) public onlyByLocker {
        require(vaultId == lockData.vaultId);

        // TODO: updatePosition
        // updateAccountDelta(false, tradeAmount);
        updateAccountDelta(true, entryUpdate);
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
        updateAccountDelta(true, marginAmount);
    }

    function take(bool isQuoteAsset, address to, uint256 amount) public onlyByLocker {
        updateAccountDelta(isQuoteAsset, int256(amount));

        address currency;

        if (isQuoteAsset) {
            currency = pairs[lockData.pairId].quoteAsset.tokenAddress;
        } else {
            currency = pairs[lockData.pairId].baseAsset.tokenAddress;
        }
        IERC20(currency).transfer(to, amount);
    }

    function settle(bool isQuoteAsset) public onlyByLocker returns (uint256 paid) {
        address currency;
        uint256 reservesBefore;

        if (isQuoteAsset) {
            currency = pairs[lockData.pairId].quoteAsset.tokenAddress;
            reservesBefore = lockData.quoteReserveBefore;
        } else {
            currency = pairs[lockData.pairId].baseAsset.tokenAddress;
            reservesBefore = lockData.baseReserveBefore;
        }

        uint256 reserveAfter = IERC20(currency).balanceOf(address(this));

        paid = reserveAfter - reservesBefore;

        updateAccountDelta(isQuoteAsset, -int256(paid));
    }

    function supply(bool isQuoteAsset, uint256 amount) public onlyByLocker {
        updateAccountDelta(isQuoteAsset, int256(amount));
    }

    function withdraw(bool isQuoteAsset, uint256 amount) public onlyByLocker {
        updateAccountDelta(isQuoteAsset, -int256(amount));
    }

    function validate(uint256 _vaultId) internal view {
        // custom validation
    }

    function updateAccountDelta(bool isQuoteAsset, int256 delta) internal {
        if (delta == 0) return;

        address locker = lockData.locker;
        int256 current = isQuoteAsset ? lockData.quoteDelta : lockData.baseDelta;
        int256 next = current + delta;

        if (next == 0) {
            lockData.deltaCount--;
        } else if (current == 0) {
            lockData.deltaCount++;
        }

        if (isQuoteAsset) {
            lockData.quoteDelta = next;
        } else {
            lockData.baseDelta = next;
        }
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
