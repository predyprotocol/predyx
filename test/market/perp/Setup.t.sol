// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import "../../pool/Setup.t.sol";
import "../../../src/interfaces/ISettlement.sol";
import "../../../src/PerpMarket.sol";
import "../../../src/settlements/UniswapSettlement.sol";
import "../../../src/settlements/DirectSettlement.sol";
import "../../../src/libraries/market/LimitOrder.sol";
import {GeneralOrderLib} from "../../../src/libraries/market/GeneralOrderLib.sol";
import "../../../src/libraries/Constants.sol";
import {SigUtils} from "../../utils/SigUtils.sol";

contract TestPerpMarket is TestPool, SigUtils {
    using GeneralOrderLib for GeneralOrder;

    UniswapSettlement settlement;
    DirectSettlement directSettlement;
    PerpMarket fillerMarket;
    IPermit2 permit2;
    LimitOrderValidator limitOrderValidator;
    bytes32 DOMAIN_SEPARATOR;

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
        directSettlement = new DirectSettlement(predyPool);

        pairId = registerPair(address(currency1));

        fillerMarket = new PerpMarket(predyPool, address(currency1), address(permit2));

        currency0.approve(address(permit2), type(uint256).max);
        currency1.approve(address(permit2), type(uint256).max);

        currency0.approve(address(fillerMarket), type(uint256).max);
        currency1.approve(address(fillerMarket), type(uint256).max);

        currency0.approve(address(directSettlement), type(uint256).max);
        currency1.approve(address(directSettlement), type(uint256).max);

        limitOrderValidator = new LimitOrderValidator();
    }

    function calculateLimitPrice(uint256 quoteAmount, uint256 baseAmount) internal pure returns (uint256) {
        return quoteAmount * Constants.Q96 / baseAmount;
    }

    function _toPermit(GeneralOrder memory order)
        internal
        view
        returns (ISignatureTransfer.PermitTransferFrom memory)
    {
        uint256 amount = order.marginAmount > 0 ? uint256(order.marginAmount) : 0;

        return ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(currency1), amount: amount}),
            nonce: order.info.nonce,
            deadline: order.info.deadline
        });
    }

    function _createSignedOrder(GeneralOrder memory marketOrder, uint256 fromPrivateKey)
        internal
        view
        returns (IFillerMarket.SignedOrder memory signedOrder)
    {
        bytes32 witness = marketOrder.hash();

        bytes memory sig = getPermitSignature(
            fromPrivateKey,
            _toPermit(marketOrder),
            address(fillerMarket),
            GeneralOrderLib.PERMIT2_ORDER_TYPE,
            witness,
            DOMAIN_SEPARATOR
        );

        signedOrder = IFillerMarket.SignedOrder(abi.encode(marketOrder), sig);
    }
}
