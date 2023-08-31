// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./IPoolManager.sol";
import "./IHook.sol";
import "./IExecutor.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external ;

    function balanceOf(address account) external view returns (uint256);
}

contract PoolManager is IPoolManager {
    struct Pair {
        address pool;
    }

    IPoolManager.LockData public lockData;

    mapping(address locker => mapping(address currency => int256 currencyDelta)) public currencyDelta;

    mapping(address currency => uint256) public reservesOf;

    modifier onlyByLocker() {
        address locker = lockData.locker;
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    constructor(
    ) {
    }

    function lock(
        IPoolManager.SignedOrder[] memory orders,
        bytes memory callbackData
    ) public {
        // TODO: push lock
        lockData.locker = msg.sender;

        for(uint256 i;i < orders.length;i++) {
            // TODO: check signature

            // TODO: call lock aquired
            IHook(msg.sender).lockAquired(orders[i]);
        }

        IExecutor(msg.sender).settleCallback(callbackData);

        // TODO: pop lock data
        lockData.locker = address(0);

        if(lockData.deltaCount != 0) revert CurrencyNotSettled();

        for(uint256 i;i < orders.length;i++) {
            uint256 vaultId = orders[i].vaultId;

            validate(vaultId);
        }
    }

    function updatePerpPosition(
        address currency0,
        address currency1,
        int256 tradeAmount,
        int256 entryUpdate
    ) public onlyByLocker {
        // TODO: updatePosition
        updateAccountDelta(currency0, tradeAmount);
        updateAccountDelta(currency1, entryUpdate);
    }

    function addDelta(
        uint256 a,
        int256 b
    ) internal returns (uint256) {
        if(b >= 0) {
            return a + uint256(b);
        } else {
            return a + uint256(-b);
        }
    }

    function take(
        address currency,
        address to,
        uint256 amount
    ) public onlyByLocker {
        updateAccountDelta(currency, int256(amount));
        reservesOf[currency] -= amount;
        IERC20(currency).transfer(to, amount);
    }

    function settle(
        address currency
    ) public onlyByLocker returns (uint256 paid) {
        uint256 reservesBefore = reservesOf[currency];
        reservesOf[currency] = IERC20(currency).balanceOf(address(this));

        paid = reservesOf[currency] - reservesBefore;

        updateAccountDelta(currency, -int256(paid));
    }


    function supply(
        address currency,
        uint256 amount
    ) public onlyByLocker {
        reservesOf[currency] += amount;
    }

    function withdraw(
        address currency,
        uint256 amount
    ) public onlyByLocker {
        reservesOf[currency] -= amount;
    }

    function validate(
        uint256 _vaultId
    ) internal view {
        // custom validation
    }

    function updateAccountDelta(address currency, int256 delta) internal {
        if (delta == 0) return;

        address locker = lockData.locker;
        int256 current = currencyDelta[locker][currency];
        int256 next = current + delta;

        if (next == 0) {
            lockData.deltaCount--;
        } else if (current == 0) {
            lockData.deltaCount++;
        }

        currencyDelta[locker][currency] = next;
    }


    /*
    function updatePerpPosition(
    ) public onlyByLocker {
    }

    function updateSqrtPosition(
    ) public onlyByLocker {
        // mint sqrt or burn sqrt
        // pool.mint() or pool.burn()
    }

    // TODO: mint power perp
    function mint(
    ) public onlyByLocker {
    }

    function take(
    ) public onlyByLocker {
        Currency.updatePosition();
    }

    function settle(
    ) public onlyByLocker {
        // TODO: decrease currency delta
    }
    */
}


contract PredyXHook {
    constructor(
    ) {
    }

    function lockAquired(
        IPoolManager.SignedOrder memory order
    ) public {
        lockAquiredTrade(order);
    }

    function settleCallback(
        bytes memory callbackData
    ) public {
    }

    function lockAquiredTrade(
        IPoolManager.SignedOrder memory order
    ) internal {
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
