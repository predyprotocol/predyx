// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {ISignatureTransfer} from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {GammaOrder} from "../../src/markets/gamma/GammaOrder.sol";
import {PredictOrder} from "../../src/markets/predict/PredictOrder.sol";
import {OrderInfo} from "../../src/libraries/orders/OrderInfoLib.sol";

contract SigUtils is Test {
    string constant _PERMIT_TRANSFER_FROM_WITNESS_TYPEHASH_STUB =
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,";

    bytes32 internal constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    function _toPermit(GammaOrder memory order) internal pure returns (ISignatureTransfer.PermitTransferFrom memory) {
        return _toPermit(order.entryTokenAddress, order.marginAmount, order.info);
    }

    function _toPermit(PredictOrder memory order)
        internal
        pure
        returns (ISignatureTransfer.PermitTransferFrom memory)
    {
        return _toPermit(order.entryTokenAddress, int256(order.marginAmount), order.info);
    }

    function _toPermit(address tokenAddress, int256 marginAmount, OrderInfo memory orderInfo)
        internal
        pure
        returns (ISignatureTransfer.PermitTransferFrom memory)
    {
        uint256 amount = marginAmount > 0 ? uint256(marginAmount) : 0;

        return ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: tokenAddress, amount: amount}),
            nonce: orderInfo.nonce,
            deadline: orderInfo.deadline
        });
    }

    function _hashTokenPermissions(ISignatureTransfer.TokenPermissions memory permitted)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permitted));
    }

    function getPermitSignature(
        uint256 privateKey,
        ISignatureTransfer.PermitTransferFrom memory permit,
        address spender,
        string memory witnessTypeHash,
        bytes32 witness,
        bytes32 domainSeparator
    ) internal pure returns (bytes memory sig) {
        bytes32 typeHash = keccak256(abi.encodePacked(_PERMIT_TRANSFER_FROM_WITNESS_TYPEHASH_STUB, witnessTypeHash));

        bytes32 msgHash = ECDSA.toTypedDataHash(
            domainSeparator,
            keccak256(
                abi.encode(
                    typeHash, _hashTokenPermissions(permit.permitted), spender, permit.nonce, permit.deadline, witness
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        sig = bytes.concat(r, s, bytes1(v));
    }

    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    function _getPermitVer1Signature(
        uint256 privateKey,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline,
        bytes32 domainSeparator
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 msgHash = ECDSA.toTypedDataHash(
            domainSeparator, keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline))
        );

        (v, r, s) = vm.sign(privateKey, msgHash);
    }
}
