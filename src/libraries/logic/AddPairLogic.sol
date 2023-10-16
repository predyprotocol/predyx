// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "../Perp.sol";
import "../DataType.sol";
import "../../tokenization/SupplyToken.sol";
import "../../types/GlobalData.sol";

library AddPairLogic {
    struct AddPairParams {
        address marginId;
        address poolOwner;
        address uniswapPool;
        address priceFeed;
        uint8 fee;
        Perp.AssetRiskParams assetRiskParams;
        InterestRateModel.IRMParams stableIrmParams;
        InterestRateModel.IRMParams underlyingIrmParams;
    }

    error InvalidUniswapPool();

    event PairAdded(uint256 pairId, address marginId, address uniswapPool);
    event PairGroupAdded(uint256 id, address stableAsset);
    event AssetRiskParamsUpdated(uint256 pairId, Perp.AssetRiskParams riskParams);
    event IRMParamsUpdated(
        uint256 pairId, InterestRateModel.IRMParams stableIrmParams, InterestRateModel.IRMParams underlyingIrmParams
    );
    event FeeRatioUpdated(uint256 pairId, uint8 feeRatio);
    event PoolOwnerUpdated(uint256 pairId, address poolOwner);

    /**
     * @notice Initialized global data counts
     * @param _global Global data
     */
    function initializeGlobalData(GlobalDataLibrary.GlobalData storage _global) external {
        _global.pairsCount = 1;
        _global.vaultCount = 1;
    }

    /**
     * @notice Adds token pair
     */
    function addPair(
        GlobalDataLibrary.GlobalData storage _global,
        mapping(address => bool) storage allowedUniswapPools,
        AddPairParams memory _addPairParam
    ) external returns (uint256 pairId) {
        pairId = _global.pairsCount;

        require(pairId < Constants.MAX_PAIRS, "MAXP");

        // Checks the pair group exists
        // PairGroupLib.validatePairGroupId(_global, _addPairParam.pairGroupId);

        IUniswapV3Pool uniswapPool = IUniswapV3Pool(_addPairParam.uniswapPool);

        address stableTokenAddress = _addPairParam.marginId;

        IUniswapV3Factory uniswapV3Factory = IUniswapV3Factory(_global.uniswapFactory);

        // check the uniswap pool is registered in UniswapV3Factory
        if (
            uniswapV3Factory.getPool(uniswapPool.token0(), uniswapPool.token1(), uniswapPool.fee())
                != _addPairParam.uniswapPool
        ) {
            revert InvalidUniswapPool();
        }

        require(uniswapPool.token0() == stableTokenAddress || uniswapPool.token1() == stableTokenAddress, "C3");

        bool isMarginZero = uniswapPool.token0() == stableTokenAddress;

        _storePairStatus(
            stableTokenAddress,
            _global.pairs,
            pairId,
            isMarginZero ? uniswapPool.token1() : uniswapPool.token0(),
            isMarginZero,
            _addPairParam
        );

        allowedUniswapPools[_addPairParam.uniswapPool] = true;

        _global.pairsCount++;

        emit PairAdded(pairId, _addPairParam.marginId, _addPairParam.uniswapPool);
    }

    function updateFeeRatio(Perp.PairStatus storage _pairStatus, uint8 _feeRatio) external {
        validateFeeRatio(_feeRatio);

        _pairStatus.feeRatio = _feeRatio;

        emit FeeRatioUpdated(_pairStatus.id, _feeRatio);
    }

    function updatePoolOwner(Perp.PairStatus storage _pairStatus, address _poolOwner) external {
        validatePoolOwner(_poolOwner);

        _pairStatus.poolOwner = _poolOwner;

        emit PoolOwnerUpdated(_pairStatus.id, _poolOwner);
    }

    function updateAssetRiskParams(Perp.PairStatus storage _pairStatus, Perp.AssetRiskParams memory _riskParams)
        external
    {
        validateRiskParams(_riskParams);

        _pairStatus.riskParams.riskRatio = _riskParams.riskRatio;
        _pairStatus.riskParams.rangeSize = _riskParams.rangeSize;
        _pairStatus.riskParams.rebalanceThreshold = _riskParams.rebalanceThreshold;

        emit AssetRiskParamsUpdated(_pairStatus.id, _riskParams);
    }

    function updateIRMParams(
        Perp.PairStatus storage _pairStatus,
        InterestRateModel.IRMParams memory _stableIrmParams,
        InterestRateModel.IRMParams memory _underlyingIrmParams
    ) external {
        validateIRMParams(_stableIrmParams);
        validateIRMParams(_underlyingIrmParams);

        _pairStatus.quotePool.irmParams = _stableIrmParams;
        _pairStatus.basePool.irmParams = _underlyingIrmParams;

        emit IRMParamsUpdated(_pairStatus.id, _stableIrmParams, _underlyingIrmParams);
    }

    function _storePairStatus(
        address marginId,
        mapping(uint256 => Perp.PairStatus) storage _pairs,
        uint256 _pairId,
        address _tokenAddress,
        bool _isMarginZero,
        AddPairParams memory _addPairParam
    ) internal {
        validateRiskParams(_addPairParam.assetRiskParams);
        validateFeeRatio(_addPairParam.fee);

        require(_pairs[_pairId].id == 0, "AAA");

        _pairs[_pairId] = Perp.PairStatus(
            _pairId,
            marginId,
            _addPairParam.poolOwner,
            Perp.AssetPoolStatus(
                marginId,
                deploySupplyToken(marginId),
                ScaledAsset.createAssetStatus(),
                _addPairParam.stableIrmParams,
                0,
                0
            ),
            Perp.AssetPoolStatus(
                _tokenAddress,
                deploySupplyToken(_tokenAddress),
                ScaledAsset.createAssetStatus(),
                _addPairParam.underlyingIrmParams,
                0,
                0
            ),
            _addPairParam.assetRiskParams,
            Perp.createAssetStatus(
                _addPairParam.uniswapPool,
                -_addPairParam.assetRiskParams.rangeSize,
                _addPairParam.assetRiskParams.rangeSize
            ),
            _addPairParam.priceFeed,
            _isMarginZero,
            _addPairParam.fee,
            block.timestamp
        );

        emit AssetRiskParamsUpdated(_pairId, _addPairParam.assetRiskParams);
        emit IRMParamsUpdated(_pairId, _addPairParam.stableIrmParams, _addPairParam.underlyingIrmParams);
    }

    function deploySupplyToken(address _tokenAddress) internal returns (address) {
        IERC20Metadata erc20 = IERC20Metadata(_tokenAddress);

        return address(
            new SupplyToken(
                        address(this),
                        string.concat("Predy6-Supply-", erc20.name()),
                        string.concat("p", erc20.symbol()),
                        erc20.decimals()
                        )
        );
    }

    function validateFeeRatio(uint8 _fee) internal pure {
        require(0 <= _fee && _fee <= 20, "FEE");
    }

    function validatePoolOwner(address _poolOwner) internal pure {
        require(_poolOwner != address(0), "ADDZ");
    }

    function validateRiskParams(Perp.AssetRiskParams memory _assetRiskParams) internal pure {
        require(1e8 < _assetRiskParams.riskRatio && _assetRiskParams.riskRatio <= 10 * 1e8, "C0");

        require(_assetRiskParams.rangeSize > 0 && _assetRiskParams.rebalanceThreshold > 0, "C0");
    }

    function validateIRMParams(InterestRateModel.IRMParams memory _irmParams) internal pure {
        require(
            _irmParams.baseRate <= 1e18 && _irmParams.kinkRate <= 1e18 && _irmParams.slope1 <= 1e18
                && _irmParams.slope2 <= 10 * 1e18,
            "C4"
        );
    }
}
