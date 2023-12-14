// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "../../pool/Setup.t.sol";
import "../../../src/interfaces/ISettlement.sol";
import {IFillerMarket} from "../../../src/interfaces/IFillerMarket.sol";
import {PerpMarket} from "../../../src/markets/perp/PerpMarket.sol";
import "../../../src/settlements/UniswapSettlement.sol";
import "../../../src/settlements/DirectSettlement.sol";
import "../../../src/markets/validators/LimitOrderValidator.sol";
import {PerpOrder, PerpOrderLib} from "../../../src/markets/perp/PerpOrder.sol";
import "../../../src/libraries/Constants.sol";
import {SigUtils} from "../../utils/SigUtils.sol";
import "../../mocks/MockPriceFeed.sol";
import {OrderValidatorUtils} from "../../utils/OrderValidatorUtils.sol";

interface USDC {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
}

contract TestPerpMarket is Test, SigUtils, OrderValidatorUtils {
    using PerpOrderLib for PerpOrder;

    uint256 internal _arbitrumFork;
    string internal _arbitrumRPCURL = vm.envString("ARBITRUM_RPC_URL");

    uint256 internal constant RISK_RATIO = 109544511;

    IPermit2 internal _permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    IUniswapV3Factory internal _uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    IUniswapV3Pool internal _uniswapPool = IUniswapV3Pool(0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443);
    USDC internal _usdc = USDC(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    ERC20 internal _weth = ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    DirectSettlement settlement;
    PerpMarket perpMarket;
    PredyPool _predyPool;
    LimitOrderValidator limitOrderValidator;
    bytes32 DOMAIN_SEPARATOR;

    uint256 pairId;

    uint256 _fromPrivateKey;
    address _from;

    function setUp() public virtual {
        _arbitrumFork = vm.createFork(_arbitrumRPCURL);
        vm.selectFork(_arbitrumFork);
        vm.rollFork(145646168);

        _fromPrivateKey = 0x12341234;
        _from = vm.addr(_fromPrivateKey);

        // Gets tokens
        deal(address(_usdc), address(this), 10000 * 1e6);
        deal(address(_usdc), _from, 10000 * 1e6);
        deal(address(_weth), address(this), 1000 * 1e18);

        _predyPool = new PredyPool();
        _predyPool.initialize(address(_uniswapFactory));
        RevertSettlement revertSettlement = new RevertSettlement(_predyPool);
        PredyPoolQuoter predyPoolQuoter = new PredyPoolQuoter(_predyPool, address(revertSettlement));

        DOMAIN_SEPARATOR = _permit2.DOMAIN_SEPARATOR();

        settlement = new DirectSettlement(_predyPool, address(this));

        pairId = registerPair(address(_usdc), address(0));

        perpMarket = new PerpMarket(_predyPool, address(_permit2), address(this), address(predyPoolQuoter));
        perpMarket.updateQuoteTokenMap(1);

        limitOrderValidator = new LimitOrderValidator();

        _weth.approve(address(_predyPool), type(uint256).max);
        _usdc.approve(address(_predyPool), type(uint256).max);
        _usdc.approve(address(perpMarket), type(uint256).max);

        _weth.approve(address(settlement), type(uint256).max);
        _usdc.approve(address(settlement), type(uint256).max);

        _predyPool.supply(1, true, 5000 * 1e6);
        _predyPool.supply(1, false, 1e18);
    }

    function registerPair(address marginId, address priceFeed) public returns (uint256) {
        InterestRateModel.IRMParams memory irmParams = InterestRateModel.IRMParams(1e16, 9 * 1e17, 5 * 1e17, 1e18);

        return _predyPool.registerPair(
            AddPairLogic.AddPairParams(
                marginId,
                address(this),
                address(_uniswapPool),
                // set up oracle
                priceFeed,
                false,
                0,
                Perp.AssetRiskParams(RISK_RATIO, 1000, 500, 10050, 10500),
                irmParams,
                irmParams
            )
        );
    }

    function _createSignedOrder(PerpOrder memory order, uint256 fromPrivateKey)
        internal
        view
        returns (IFillerMarket.SignedOrder memory signedOrder)
    {
        bytes32 witness = order.hash();

        bytes memory sig = getPermitSignature(
            fromPrivateKey,
            _toPermit(order),
            address(perpMarket),
            PerpOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        signedOrder = IFillerMarket.SignedOrder(abi.encode(order), sig);
    }
}
