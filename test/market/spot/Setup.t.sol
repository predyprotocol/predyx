// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "../../pool/Setup.t.sol";
import "../../../src/interfaces/ISettlement.sol";
import "../../../src/markets/spot/SpotMarket.sol";
import "../../../src/settlements/DirectSettlement.sol";
import {
    SpotDutchOrderValidationData,
    SpotDutchOrderValidator
} from "../../../src/markets/spot/SpotDutchOrderValidator.sol";
import {SpotOrder, SpotOrderLib} from "../../../src/markets/spot/SpotOrder.sol";
import "../../../src/libraries/Constants.sol";
import {SigUtils} from "../../utils/SigUtils.sol";
import {OrderValidatorUtils} from "../../utils/OrderValidatorUtils.sol";

contract TestSpotMarket is TestPool, SigUtils, OrderValidatorUtils {
    using SpotOrderLib for SpotOrder;

    DirectSettlement settlement;
    SpotMarket fillerMarket;
    IPermit2 permit2;
    SpotDutchOrderValidator dutchOrderValidator;
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public virtual override(TestPool) {
        TestPool.setUp();

        permit2 = IPermit2(deployCode("../artifacts/Permit2.sol:Permit2"));

        DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();

        fillerMarket = new SpotMarket(address(permit2));

        settlement = new DirectSettlement(fillerMarket, address(this));

        currency0.approve(address(permit2), type(uint256).max);
        currency1.approve(address(permit2), type(uint256).max);

        currency0.approve(address(fillerMarket), type(uint256).max);
        currency1.approve(address(fillerMarket), type(uint256).max);

        currency0.approve(address(settlement), type(uint256).max);
        currency1.approve(address(settlement), type(uint256).max);

        dutchOrderValidator = new SpotDutchOrderValidator();
    }

    function _createSignedOrder(SpotOrder memory marketOrder, uint256 fromPrivateKey)
        internal
        view
        returns (IFillerMarket.SignedOrder memory signedOrder)
    {
        bytes32 witness = marketOrder.hash();

        bytes memory sig = getPermitSignature(
            fromPrivateKey,
            _toPermit(marketOrder),
            address(fillerMarket),
            SpotOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        signedOrder = IFillerMarket.SignedOrder(abi.encode(marketOrder), sig);
    }
}
