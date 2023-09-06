// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./interfaces/IExchange.sol";
import "./interfaces/IAssetHooks.sol";
import "forge-std/console.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external;

    function transferFrom(address from, address to, uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);
}

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

            ISettlementHook(_settlementHook).settlementCallback(
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
        updateAccountDelta(pairId, isQuoteAsset, delta);
    }

    function updateAccountDelta(uint256 pairId, bool isQuoteAsset, int256 delta) internal {
        console.log(1, uint256(delta));
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

contract PerpAssetHooks {
    error PriceGreaterThanLimit();

    error PriceLessThanLimit();

    IExchange exchange;

    struct PerpAssetComposeParams {
        uint256 pairId;
        int256 tradeAmount;
        int256 limitPrice;
    }

    constructor(IExchange _exchange) {
        exchange = _exchange;
    }

    // compose and decompose
    function compose(bytes memory data) external {
        PerpAssetComposeParams memory order = abi.decode(data, (PerpAssetComposeParams));

        exchange.updatePosition(order.pairId, false, order.tradeAmount);
    }

    function addDebt(bytes memory data, int256 averagePrice) external {
        PerpAssetComposeParams memory order = abi.decode(data, (PerpAssetComposeParams));

        int256 entryUpdate = -averagePrice * order.tradeAmount / 1e18;

        // TODO: updatePosition
        exchange.updatePosition(order.pairId, true, entryUpdate);

        if (order.tradeAmount > 0 && order.limitPrice < averagePrice) {
            revert PriceGreaterThanLimit();
        } else if (order.tradeAmount < 0 && order.limitPrice > averagePrice) {
            revert PriceLessThanLimit();
        }
    }
}

contract LendingAssetHooks {
    IExchange exchange;

    struct LendingAssetComposeParams {
        uint256 pairId;
        bool isQuoterAsset;
        uint256 supplyAmount;
    }

    constructor(IExchange _exchange) {
        exchange = _exchange;
    }

    // compose and decompose
    function compose(bytes memory data) external {
        LendingAssetComposeParams memory order = abi.decode(data, (LendingAssetComposeParams));

        exchange.updatePosition(order.pairId, order.isQuoterAsset, int256(order.supplyAmount));
    }

    function addDebt(bytes memory data, int256 averagePrice) external {}
}

contract SettlementHook {
    struct SettleCallbackParams {
        uint256 pairId;
        address currency0;
        address currency1;
    }

    IExchange exchange;

    constructor(IExchange _exchange) {
        exchange = _exchange;
    }

    function settlementCallback(bytes memory callbackData, int256 quoteAmountDelta, int256 baseAmountDelta) public {
        SettleCallbackParams memory settleCallbackParams = abi.decode(callbackData, (SettleCallbackParams));

        if (baseAmountDelta > 0) {
            uint256 settleAmount = uint256(baseAmountDelta);

            uint256 takeAmount = settleAmount;

            exchange.take(true, address(this), takeAmount);

            IERC20(settleCallbackParams.currency0).transfer(address(exchange), settleAmount);

            exchange.settle(settleCallbackParams.pairId, false);
        } else {
            uint256 takeAmount = uint256(-baseAmountDelta);

            uint256 settleAmount = takeAmount;

            exchange.take(false, address(this), takeAmount);

            IERC20(settleCallbackParams.currency1).transfer(address(exchange), settleAmount);

            exchange.settle(settleCallbackParams.pairId, true);
        }
    }
}

contract DepositSettlementHook {
    struct SettleCallbackParams {
        uint256 pairId;
        bool isQuoteAsset;
        address currency;
    }

    IExchange exchange;

    constructor(IExchange _exchange) {
        exchange = _exchange;
    }

    function settlementCallback(bytes memory callbackData, int256 quoteAmountDelta, int256 baseAmountDelta) public {
        SettleCallbackParams memory settleCallbackParams = abi.decode(callbackData, (SettleCallbackParams));

        int256 settleAmount = settleCallbackParams.isQuoteAsset ? quoteAmountDelta : baseAmountDelta;

        if (settleAmount > 0) {
            IERC20(settleCallbackParams.currency).transfer(address(exchange), uint256(settleAmount));

            exchange.settle(settleCallbackParams.pairId, settleCallbackParams.isQuoteAsset);
        }
    }
}
