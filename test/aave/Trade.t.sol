// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TestAavePerp} from "./Setup.t.sol";

contract TestAavePerpTrade is TestAavePerp {

    function setUp() public virtual override(TestAavePerp) {
        TestAavePerp.setUp();
    }

    function testExecuteOrderSucceeds() public {
    }
}
