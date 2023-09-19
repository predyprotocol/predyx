// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../../src/libraries/Perp.sol";
import "../../src/libraries/ScaledAsset.sol";
import "../../src/libraries/InterestRateModel.sol";

contract PairStatusUtils {
    uint256 internal constant _RISK_RATIO = 109544511;

    function createAssetStatus(uint256 pairId, address marginId, address _weth, address _uniswapPool)
        internal
        view
        returns (Perp.PairStatus memory assetStatus)
    {
        assetStatus = Perp.PairStatus(
            pairId,
            marginId,
            address(0),
            Perp.AssetPoolStatus(
                address(0),
                address(0),
                ScaledAsset.createAssetStatus(),
                InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
                0,
                0
            ),
            Perp.AssetPoolStatus(
                _weth,
                address(0),
                ScaledAsset.createAssetStatus(),
                InterestRateModel.IRMParams(0, 9 * 1e17, 1e17, 1e18),
                0,
                0
            ),
            Perp.AssetRiskParams(_RISK_RATIO, 1000, 500),
            Perp.createAssetStatus(_uniswapPool, -100, 100),
            false,
            0,
            block.timestamp
        );
    }
}
