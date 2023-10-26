// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../pool/Setup.t.sol";
import "../../../src/interfaces/ISettlement.sol";
import "../../../src/GammaTradeMarket.sol";
import "../../../src/settlements/UniswapSettlement.sol";
import "../../../src/libraries/orders/LimitOrderValidator.sol";
import {GammaOrder, GammaOrderLib} from "../../../src/libraries/orders/GammaOrder.sol";
import "../../../src/libraries/Constants.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {SigUtils} from "../../utils/SigUtils.sol";

contract TestMarket is TestPool, SigUtils {
    using GammaOrderLib for GammaOrder;

    UniswapSettlement settlement;
    GammaTradeMarket fillerMarket;
    IPermit2 permit2;
    LimitOrderValidator limitOrderValidator;
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

        fillerMarket = new GammaTradeMarket(predyPool, address(currency1), address(permit2));

        currency0.approve(address(permit2), type(uint256).max);
        currency1.approve(address(permit2), type(uint256).max);

        currency0.approve(address(fillerMarket), type(uint256).max);
        currency1.approve(address(fillerMarket), type(uint256).max);

        limitOrderValidator = new LimitOrderValidator();
    }

    function calculateLimitPrice(uint256 quoteAmount, uint256 baseAmount) internal pure returns (uint256) {
        return quoteAmount * Constants.Q96 / baseAmount;
    }

    function _toPermit(GammaOrder memory order) internal view returns (ISignatureTransfer.PermitTransferFrom memory) {
        uint256 amount = order.marginAmount > 0 ? uint256(order.marginAmount) : 0;

        return ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(currency1), amount: amount}),
            nonce: order.info.nonce,
            deadline: order.info.deadline
        });
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
            address(fillerMarket),
            GammaOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        signedOrder = IFillerMarket.SignedOrder(abi.encode(marketOrder), sig);
    }
}
