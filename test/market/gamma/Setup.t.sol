// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "../../pool/Setup.t.sol";
import "../../../src/interfaces/ISettlement.sol";
import {IFillerMarket} from "../../../src/interfaces/IFillerMarket.sol";
import {GammaTradeMarket} from "../../../src/markets/gamma/GammaTradeMarket.sol";
import "../../../src/markets/validators/LimitOrderValidator.sol";
import {GammaOrder, GammaOrderLib} from "../../../src/markets/gamma/GammaOrder.sol";
import {GammaModifyOrder, GammaModifyOrderLib} from "../../../src/markets/gamma/GammaModifyOrder.sol";
import "../../../src/libraries/Constants.sol";
import {SigUtils} from "../../utils/SigUtils.sol";
import {OrderValidatorUtils} from "../../utils/OrderValidatorUtils.sol";

contract TestGammaMarket is TestPool, SigUtils, OrderValidatorUtils {
    using GammaOrderLib for GammaOrder;
    using GammaModifyOrderLib for GammaModifyOrder;

    GammaTradeMarket gammaTradeMarket;
    IPermit2 permit2;
    LimitOrderValidator limitOrderValidator;
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public virtual override(TestPool) {
        TestPool.setUp();

        permit2 = IPermit2(deployCode("../test-artifacts/Permit2.sol:Permit2"));

        DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();

        gammaTradeMarket = new GammaTradeMarket();

        gammaTradeMarket.initialize(predyPool, address(permit2), address(this), address(_predyPoolQuoter));

        gammaTradeMarket.updateWhitelistSettlement(address(uniswapSettlement), true);

        currency0.approve(address(permit2), type(uint256).max);
        currency1.approve(address(permit2), type(uint256).max);

        currency0.approve(address(gammaTradeMarket), type(uint256).max);
        currency1.approve(address(gammaTradeMarket), type(uint256).max);

        limitOrderValidator = new LimitOrderValidator();
    }

    function _createSignedOrder(GammaOrder memory marketOrder, uint256 fromPrivateKey)
        internal
        view
        returns (IFillerMarket.SignedOrder memory signedOrder)
    {
        bytes32 witness = marketOrder.hash();

        bytes memory sig = getPermitSignature(
            fromPrivateKey,
            _toPermit(marketOrder),
            address(gammaTradeMarket),
            GammaOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        signedOrder = IFillerMarket.SignedOrder(abi.encode(marketOrder), sig);
    }

    function _sign(GammaModifyOrder memory modifyOrder, uint256 fromPrivateKey)
        internal
        view
        returns (bytes memory sig)
    {
        bytes32 witness = modifyOrder.hash();

        sig = getPermitSignature(
            fromPrivateKey,
            _toPermit(modifyOrder),
            address(gammaTradeMarket),
            GammaModifyOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );
    }
}
