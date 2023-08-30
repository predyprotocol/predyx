// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./IPoolManager.sol";
import "./IHook.sol";

/*
contract Currency {
    function updatePosition() {

    }
}
*/

contract PoolManager is IPoolManager {
    struct Pair {
        address pool;
    }

    IPoolManager.LockData public lockData;

    mapping(address locker => mapping(address currency => int256 currencyDelta)) public currencyDelta;

    modifier onlyByLocker() {
        address locker = lockData.locker;
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    constructor(
    ) {
    }

    function lock(
        IPoolManager.SignedOrder[] memory orders
    ) public {
        // TODO: push lock
        lockData.locker = msg.sender;

        // TODO: call lock aquired
        IHook(msg.sender).lockAquired(orders);

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


    function take(
        address currency,
        uint256 amount
    ) public onlyByLocker {
        updateAccountDelta(currency, amount);
    }

    function settle(
        address currency,
        uint256 amount
    ) public onlyByLocker {
        updateAccountDelta(currency, -int256(amount));
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

    function supply(
    ) public onlyByLocker {
    }

    function withdraw(
    ) public onlyByLocker {
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
        IPoolManager.SignedOrder[] memory orders
    ) public {
        lockAquiredTrade(orders);
    }

    function lockAquiredTrade(
        IPoolManager.SignedOrder[] memory orders
    ) internal {
        /*
        for(uint256 i;i < orders.length;i++) {
            controller.updatePerpPosition();
            controller.updateSqrtPosition();
        }

        swap();

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
