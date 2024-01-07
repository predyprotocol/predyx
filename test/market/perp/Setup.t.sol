// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "../../pool/Setup.t.sol";
import "../../../src/interfaces/ISettlement.sol";
import {IFillerMarket} from "../../../src/interfaces/IFillerMarket.sol";
import {PerpMarket} from "../../../src/markets/perp/PerpMarket.sol";
import "../../../src/settlements/UniswapSettlement.sol";
import "../../../src/markets/validators/LimitOrderValidator.sol";
import {PerpOrder, PerpOrderLib} from "../../../src/markets/perp/PerpOrder.sol";
import "../../../src/libraries/Constants.sol";
import {SigUtils} from "../../utils/SigUtils.sol";
import {OrderValidatorUtils} from "../../utils/OrderValidatorUtils.sol";

contract TestPerpMarket is TestPool, SigUtils, OrderValidatorUtils {
    using PerpOrderLib for PerpOrder;

    UniswapSettlement settlement;
    PerpMarket perpMarket;
    IPermit2 permit2;
    LimitOrderValidator limitOrderValidator;
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public virtual override(TestPool) {
        TestPool.setUp();

        permit2 = IPermit2(deployCode("../test-artifacts/Permit2.sol:Permit2"));

        DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();

        settlement = uniswapSettlement;

        perpMarket = new PerpMarket();
        perpMarket.initialize(predyPool, address(permit2), address(this), address(_predyPoolQuoter));
        perpMarket.updateWhitelistSettlement(address(settlement), true);

        currency0.approve(address(permit2), type(uint256).max);
        currency1.approve(address(permit2), type(uint256).max);

        currency0.approve(address(perpMarket), type(uint256).max);
        currency1.approve(address(perpMarket), type(uint256).max);

        limitOrderValidator = new LimitOrderValidator();
    }

    function _createSignedOrder(PerpOrder memory marketOrder, uint256 fromPrivateKey)
        internal
        view
        returns (IFillerMarket.SignedOrder memory signedOrder)
    {
        bytes32 witness = marketOrder.hash();

        bytes memory sig = getPermitSignature(
            fromPrivateKey,
            _toPermit(marketOrder),
            address(perpMarket),
            PerpOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        signedOrder = IFillerMarket.SignedOrder(abi.encode(marketOrder), sig);
    }
}
