// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "../../pool/Setup.t.sol";
import "../../../src/interfaces/ISettlement.sol";
import "../../../src/PerpMarket.sol";
import "../../../src/settlements/UniswapSettlement.sol";
import "../../../src/settlements/DirectSettlement.sol";
import "../../../src/libraries/orders/PerpLimitOrderValidator.sol";
import {PerpOrder, PerpOrderLib} from "../../../src/libraries/orders/PerpOrder.sol";
import "../../../src/libraries/Constants.sol";
import {SigUtils} from "../../utils/SigUtils.sol";
import "../../mocks/MockPriceFeed.sol";

contract TestPerpMarket is TestPool, SigUtils {
    using PerpOrderLib for PerpOrder;

    UniswapSettlement settlement;
    DirectSettlement directSettlement;
    PerpMarket fillerMarket;
    IPermit2 permit2;
    PerpLimitOrderValidator limitOrderValidator;
    bytes32 DOMAIN_SEPARATOR;

    uint256 pairId;

    MockPriceFeed priceFeed;

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

        priceFeed = new MockPriceFeed();
        priceFeed.setSqrtPrice(2 ** 96);
        pairId = registerPair(address(currency1), address(priceFeed));

        fillerMarket = new PerpMarket(predyPool, address(permit2));
        fillerMarket.updateQuoteTokenMap(1);

        currency0.approve(address(permit2), type(uint256).max);
        currency1.approve(address(permit2), type(uint256).max);

        currency0.approve(address(fillerMarket), type(uint256).max);
        currency1.approve(address(fillerMarket), type(uint256).max);

        currency0.approve(address(directSettlement), type(uint256).max);
        currency1.approve(address(directSettlement), type(uint256).max);

        limitOrderValidator = new PerpLimitOrderValidator();

        predyPool.supply(pairId, true, 1e18);
        predyPool.supply(pairId, false, 1e18);
    }

    function calculateLimitPrice(uint256 quoteAmount, uint256 baseAmount) internal pure returns (uint256) {
        return quoteAmount * Constants.Q96 / baseAmount;
    }

    function _toPermit(PerpOrder memory order) internal view returns (ISignatureTransfer.PermitTransferFrom memory) {
        uint256 amount = order.marginAmount > 0 ? uint256(order.marginAmount) : 0;

        return ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(currency1), amount: amount}),
            nonce: order.info.nonce,
            deadline: order.info.deadline
        });
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
            address(fillerMarket),
            PerpOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        signedOrder = IFillerMarket.SignedOrder(abi.encode(order), sig);
    }
}
