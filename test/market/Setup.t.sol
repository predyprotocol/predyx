// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../pool/Setup.t.sol";
import "../../src/FillerMarket.sol";

contract TestMarket is TestPool {
    FillerMarket fillerMarket;

    function setUp() public virtual override(TestPool) {
        TestPool.setUp();

        fillerMarket = new FillerMarket(predyPool);
    }
}
