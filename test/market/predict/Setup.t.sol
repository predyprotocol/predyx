// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "../../pool/Setup.t.sol";
import "../../../src/interfaces/ISettlement.sol";
import "../../../src/markets/predict/PredictMarket.sol";
import "../../../src/settlements/UniswapSettlement.sol";
import "../../../src/markets/predict/PredictDutchOrderValidator.sol";
import {PredictOrder, PredictOrderLib} from "../../../src/markets/predict/PredictOrder.sol";
import "../../../src/libraries/Constants.sol";
import {SigUtils} from "../../utils/SigUtils.sol";
import {OrderValidatorUtils} from "../../utils/OrderValidatorUtils.sol";

contract TestPredictMarket is TestPool, SigUtils, OrderValidatorUtils {
    using PredictOrderLib for PredictOrder;

    UniswapSettlement settlement;
    PredictMarket fillerMarket;
    IPermit2 permit2;
    PredictDutchOrderValidator dutchOrderValidator;
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public virtual override(TestPool) {
        TestPool.setUp();

        address swapRouter = deployCode(
            "../node_modules/@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol:SwapRouter",
            abi.encode(uniswapFactory, address(currency0))
        );

        permit2 = IPermit2(deployCode("../artifacts/Permit2.sol:Permit2"));

        DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();

        settlement = new UniswapSettlement(predyPool, swapRouter);

        fillerMarket = new PredictMarket(predyPool, address(permit2));

        currency0.approve(address(permit2), type(uint256).max);
        currency1.approve(address(permit2), type(uint256).max);

        currency0.approve(address(fillerMarket), type(uint256).max);
        currency1.approve(address(fillerMarket), type(uint256).max);

        dutchOrderValidator = new PredictDutchOrderValidator();
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
}
