// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {L2GammaDecoder} from "../../../src/markets/gamma/L2GammaDecoder.sol";
import {OrderValidatorUtils} from "../../utils/OrderValidatorUtils.sol";

contract TestL2GammaDecoder is Test, OrderValidatorUtils {
    function testSucceedsToDecodeGammaParams() public {
        (bool a, uint64 b, uint32 c, uint32 d, uint32 e, uint32 f, uint16 g, uint32 h) = L2GammaDecoder
            .decodeGammaModifyParam(bytes32(0x0006000000000007000000050000000400000003000000020000000000000001));

        assertEq(a, false);
        assertEq(b, 1);
        assertEq(c, 2);
        assertEq(d, 3);
        assertEq(e, 4);
        assertEq(f, 5);
        assertEq(g, 6);
        assertEq(h, 7);
    }
}
