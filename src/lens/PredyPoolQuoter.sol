// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "../interfaces/IPredyPool.sol";
import "../interfaces/IOrderValidator.sol";
import "../base/BaseHookCallback.sol";

/**
 * @notice Quoter contract for PredyPool
 */
contract PredyPoolQuoter is BaseHookCallback {
    using GeneralOrderLib for GeneralOrder;

    address _revertSettlement;

    constructor(IPredyPool _predyPool, address revertSettlement) BaseHookCallback(_predyPool) {
        _revertSettlement = revertSettlement;
    }

    function predyTradeAfterCallback(IPredyPool.TradeParams memory, IPredyPool.TradeResult memory tradeResult)
        external
        override(BaseHookCallback)
        onlyPredyPool
    {
        bytes memory data = abi.encode(tradeResult);

        assembly {
            revert(add(32, data), mload(data))
        }
    }

    /**
     * @notice Quotes trade
     * @param tradeParams The trade details
     * @param settlementData The route of settlement created by filler
     */
    function quoteTrade(IPredyPool.TradeParams memory tradeParams, ISettlement.SettlementData memory settlementData)
        external
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        try _predyPool.trade(tradeParams, settlementData) {}
        catch (bytes memory reason) {
            tradeResult = _parseRevertReasonAsTradeResult(reason);
        }
    }

    function quoteBaseAmountDelta(IPredyPool.TradeParams memory tradeParams) external returns (int256) {
        try _predyPool.trade(tradeParams, ISettlement.SettlementData(_revertSettlement, "")) {}
        catch (bytes memory reason) {
            return _parseRevertReasonAsBaseAmountDelta(reason);
        }
    }

    function quotePairStatus(uint256 pairId) external returns (Perp.PairStatus memory pairStatus) {
        try _predyPool.revertPairStatus(pairId) {}
        catch (bytes memory reason) {
            pairStatus = _parseRevertReasonAsPairStatus(reason);
        }
    }

    function quoteVaultStatus(uint256 vaultId) external returns (IPredyPool.VaultStatus memory vaultStatus) {
        try _predyPool.revertVaultStatus(vaultId) {}
        catch (bytes memory reason) {
            vaultStatus = _parseRevertReasonAsVaultStatus(reason);
        }
    }

    /// @notice Return the tradeResult of given abi-encoded trade result
    /// @param tradeResult abi-encoded order, including `reactor` as the first encoded struct member
    function _parseRevertReasonAsTradeResult(bytes memory reason)
        private
        pure
        returns (IPredyPool.TradeResult memory tradeResult)
    {
        if (reason.length < 192) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (IPredyPool.TradeResult));
        }
    }

    function _parseRevertReasonAsBaseAmountDelta(bytes memory reason) private pure returns (int256) {
        if (reason.length < 192) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (int256));
        }
    }

    function _parseRevertReasonAsPairStatus(bytes memory reason)
        private
        pure
        returns (Perp.PairStatus memory pairStatus)
    {
        if (reason.length < 192) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (Perp.PairStatus));
        }
    }

    function _parseRevertReasonAsVaultStatus(bytes memory reason)
        private
        pure
        returns (IPredyPool.VaultStatus memory vaultStatus)
    {
        if (reason.length < 192) {
            assembly {
                revert(add(32, reason), mload(reason))
            }
        } else {
            return abi.decode(reason, (IPredyPool.VaultStatus));
        }
    }
}
