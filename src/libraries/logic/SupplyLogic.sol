// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IPredyPool.sol";
import "../../interfaces/ISupplyToken.sol";
import "../DataType.sol";
import "../ScaledAsset.sol";
import "../ApplyInterestLib.sol";
import "../../types/GlobalData.sol";
import "forge-std/console.sol";

library SupplyLogic {
    using ScaledAsset for ScaledAsset.AssetStatus;
    using GlobalDataLibrary for GlobalDataLibrary.GlobalData;

    event TokenSupplied(address account, uint256 pairId, bool isStable, uint256 suppliedAmount);
    event TokenWithdrawn(address account, uint256 pairId, bool isStable, uint256 finalWithdrawnAmount);

    function supply(GlobalDataLibrary.GlobalData storage globalData, uint256 _pairId, uint256 _amount, bool _isStable)
        external
        returns (uint256 mintAmount)
    {
        // Checks pair exists
        globalData.validate(_pairId);

        console.log(1);

        // Checks amount is not 0
        if (_amount <= 0) {
            revert IPredyPool.InvalidAmount();
        }

        console.log(2);

        // Updates interest rate related to the pair
        ApplyInterestLib.applyInterestForToken(globalData.pairs, _pairId);

        console.log(3);

        Perp.PairStatus storage pair = globalData.pairs[_pairId];

        if (_isStable) {
            mintAmount = _supply(pair.quotePool, _amount);
        } else {
            mintAmount = _supply(pair.basePool, _amount);
        }

        emit TokenSupplied(msg.sender, pair.id, _isStable, _amount);
    }

    function _supply(Perp.AssetPoolStatus storage _pool, uint256 _amount) internal returns (uint256 mintAmount) {
        mintAmount = _pool.tokenStatus.addAsset(_amount);

        TransferHelper.safeTransferFrom(_pool.token, msg.sender, address(this), _amount);

        console.log(4);

        ISupplyToken(_pool.supplyTokenAddress).mint(msg.sender, mintAmount);
    }

    function withdraw(GlobalDataLibrary.GlobalData storage globalData, uint256 _pairId, uint256 _amount, bool _isStable)
        external
        returns (uint256 finalburntAmount, uint256 finalWithdrawalAmount)
    {
        // Checks pair exists
        globalData.validate(_pairId);
        // Checks amount is not 0
        require(_amount > 0, "AZ");
        // Updates interest rate related to the pair
        ApplyInterestLib.applyInterestForToken(globalData.pairs, _pairId);

        Perp.PairStatus storage pair = globalData.pairs[_pairId];

        if (_isStable) {
            (finalburntAmount, finalWithdrawalAmount) = _withdraw(pair.quotePool, _amount);
        } else {
            (finalburntAmount, finalWithdrawalAmount) = _withdraw(pair.basePool, _amount);
        }

        emit TokenWithdrawn(msg.sender, pair.id, _isStable, finalWithdrawalAmount);
    }

    function _withdraw(Perp.AssetPoolStatus storage _pool, uint256 _amount)
        internal
        returns (uint256 finalburntAmount, uint256 finalWithdrawalAmount)
    {
        address supplyTokenAddress = _pool.supplyTokenAddress;

        (finalburntAmount, finalWithdrawalAmount) =
            _pool.tokenStatus.removeAsset(IERC20(supplyTokenAddress).balanceOf(msg.sender), _amount);

        ISupplyToken(supplyTokenAddress).burn(msg.sender, finalburntAmount);

        TransferHelper.safeTransfer(_pool.token, msg.sender, finalWithdrawalAmount);
    }
}
