// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "../../pool/Setup.t.sol";
import "../../../src/interfaces/ISettlement.sol";
import "../../../src/LeveragedGammaMarket.sol";
import "../../../src/settlements/UniswapSettlement.sol";
import "../../../src/settlements/DirectSettlement.sol";
import "../../../src/libraries/orders/LimitOrderValidator.sol";
import {GammaOrder, GammaOrderLib} from "../../../src/libraries/orders/GammaOrder.sol";
import "../../../src/libraries/Constants.sol";
import {SigUtils} from "../../utils/SigUtils.sol";
import "../../mocks/MockPriceFeed.sol";

contract TestLevMarket is TestPool, SigUtils {
    using GammaOrderLib for GammaOrder;

    UniswapSettlement settlement;
    DirectSettlement directSettlement;
    LeveragedGammaMarket market;
    IPermit2 permit2;
    LimitOrderValidator limitOrderValidator;
    bytes32 DOMAIN_SEPARATOR;
    MockPriceFeed priceFeed;

    uint256 pairId;

    function setUp() public virtual override(TestPool) {
        TestPool.setUp();

        address swapRouter = deployCode(
            "../node_modules/@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol:SwapRouter",
            abi.encode(uniswapFactory, address(currency0))
        );

        permit2 = IPermit2(deployCode("../artifacts/Permit2.sol:Permit2"));

        DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();

        settlement = new UniswapSettlement(predyPool, swapRouter);
        directSettlement = new DirectSettlement(predyPool, address(this));

        market = new LeveragedGammaMarket(predyPool, address(permit2));

        currency0.approve(address(permit2), type(uint256).max);
        currency1.approve(address(permit2), type(uint256).max);

        currency0.approve(address(market), type(uint256).max);
        currency1.approve(address(market), type(uint256).max);

        currency0.approve(address(directSettlement), type(uint256).max);
        currency1.approve(address(directSettlement), type(uint256).max);

        limitOrderValidator = new LimitOrderValidator();

        priceFeed = new MockPriceFeed();
        priceFeed.setSqrtPrice(2 ** 96);
        pairId = registerPair(address(currency1), address(priceFeed));
        market.updateQuoteTokenMap(pairId);
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
            address(market),
            GammaOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        signedOrder = IFillerMarket.SignedOrder(abi.encode(marketOrder), sig);
    }
}