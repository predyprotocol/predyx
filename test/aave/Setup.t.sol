// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IPool} from "../../lib/aave-v3-core/contracts/interfaces/IPool.sol";
import {SigUtils} from "../utils/SigUtils.sol";
import "../../src/settlements/DirectSettlement.sol";
import "../../src/libraries/orders/PerpOrder.sol";
import "../../src/libraries/orders/PerpLimitOrderValidator.sol";
import {AavePerp} from "../../src/aave/AavePerp.sol";

contract TestAavePerp is Test, SigUtils {
    using PerpOrderLib for PerpOrder;

    uint256 internal _arbitrumFork;
    string internal _arbitrumRPCURL = vm.envString("ARBITRUM_RPC_URL");

    ERC20 internal _weth;
    ERC20 internal _usdc;

    IPool _pool;

    AavePerp internal _aavePerp;

    DirectSettlement internal settlement;

    PerpLimitOrderValidator limitOrderValidator;

    IPermit2 permit2;

    uint256 fromPrivateKey1;
    address from1;

    uint256 pairId;

    function setUp() public virtual {
        _arbitrumFork = vm.createFork(_arbitrumRPCURL);
        vm.selectFork(_arbitrumFork);
        vm.rollFork(145646168);

        _usdc = ERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
        _weth = ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        _pool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
        permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

        fromPrivateKey1 = 0x12341234;
        from1 = vm.addr(fromPrivateKey1);

        // Gets tokens
        vm.startPrank(0x5bdf85216ec1e38D6458C870992A69e38e03F7Ef);
        _usdc.transfer(address(this), 10000 * 1e6);
        _usdc.transfer(from1, 1000 * 1e6);
        vm.stopPrank();

        vm.startPrank(0x1eED63EfBA5f81D95bfe37d82C8E736b974F477b);
        _weth.transfer(address(this), 1000 * 1e18);
        vm.stopPrank();

        _aavePerp = new AavePerp(address(permit2), address(_pool));
        pairId = _aavePerp.addPair(address(_usdc), address(_weth));

        settlement = new DirectSettlement(_aavePerp, address(this));

        limitOrderValidator = new PerpLimitOrderValidator();

        vm.startPrank(from1);
        _usdc.approve(address(permit2), type(uint256).max);
        vm.stopPrank();

        _usdc.approve(address(_aavePerp), type(uint256).max);
        _usdc.approve(address(settlement), type(uint256).max);
        _weth.approve(address(settlement), type(uint256).max);
    }

    function _createSignedOrder(PerpOrder memory order, uint256 fromPrivateKey)
        internal
        view
        returns (IFillerMarket.SignedOrder memory signedOrder)
    {
        bytes32 witness = order.hash();

        bytes32 domainSeparator = permit2.DOMAIN_SEPARATOR();

        bytes memory sig = getPermitSignature(
            fromPrivateKey,
            _toPermit(order),
            address(_aavePerp),
            PerpOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            domainSeparator
        );

        signedOrder = IFillerMarket.SignedOrder(abi.encode(order), sig);
    }
}
