// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "../../pool/Setup.t.sol";
import {ISettlement} from "../../../src/interfaces/ISettlement.sol";
import {IFillerMarket} from "../../../src/interfaces/IFillerMarket.sol";
import {PredictMarket} from "../../../src/markets/predict/PredictMarket.sol";
import "../../../src/markets/validators/GeneralDutchOrderValidator.sol";
import {PredictOrder, PredictOrderLib} from "../../../src/markets/predict/PredictOrder.sol";
import {PredictCloseOrder, PredictCloseOrderLib} from "../../../src/markets/predict/PredictCloseOrder.sol";
import "../../../src/libraries/Constants.sol";
import {SigUtils} from "../../utils/SigUtils.sol";
import {OrderValidatorUtils} from "../../utils/OrderValidatorUtils.sol";

contract TestPredictMarket is TestPool, SigUtils, OrderValidatorUtils {
    using PredictOrderLib for PredictOrder;
    using PredictCloseOrderLib for PredictCloseOrder;

    PredictMarket fillerMarket;
    IPermit2 permit2;
    GeneralDutchOrderValidator dutchOrderValidator;
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public virtual override(TestPool) {
        TestPool.setUp();

        permit2 = IPermit2(deployCode("../test-artifacts/Permit2.sol:Permit2"));

        DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();

        fillerMarket = new PredictMarket();
        fillerMarket.initialize(predyPool, address(permit2), address(this), address(_predyPoolQuoter));
        fillerMarket.updateWhitelistSettlement(address(uniswapSettlement), true);

        currency0.approve(address(permit2), type(uint256).max);
        currency1.approve(address(permit2), type(uint256).max);

        currency0.approve(address(fillerMarket), type(uint256).max);
        currency1.approve(address(fillerMarket), type(uint256).max);

        dutchOrderValidator = new GeneralDutchOrderValidator();
    }

    function _createSignedOrder(PredictOrder memory marketOrder, uint256 fromPrivateKey)
        internal
        view
        returns (IFillerMarket.SignedOrder memory signedOrder)
    {
        bytes32 witness = marketOrder.hash();

        bytes memory sig = getPermitSignature(
            fromPrivateKey,
            _toPermit(marketOrder),
            address(fillerMarket),
            PredictOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        signedOrder = IFillerMarket.SignedOrder(abi.encode(marketOrder), sig);
    }

    function _createSignedOrder(PredictCloseOrder memory order, uint256 fromPrivateKey)
        internal
        view
        returns (IFillerMarket.SignedOrder memory signedOrder)
    {
        bytes32 witness = order.hash();

        bytes memory sig = getPermitSignature(
            fromPrivateKey,
            _toPermit(order),
            address(fillerMarket),
            PredictOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        signedOrder = IFillerMarket.SignedOrder(abi.encode(order), sig);
    }
}
