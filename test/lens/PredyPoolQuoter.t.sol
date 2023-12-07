// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";

contract TestPredyPoolQuoter is TestLens {
    function setUp() public override {
        TestLens.setUp();

        predyPool.createVault(1);
    }

    function testQuotePairStatus() public {
        DataType.PairStatus memory pairStatus = _predyPoolQuoter.quotePairStatus(1);

        assertEq(pairStatus.id, 1);
    }

    function testQuoteBaseAmountDeltaFails() public {
        vm.expectRevert(IPredyPool.InvalidPairId.selector);
        _predyPoolQuoter.quoteBaseAmountDelta(IPredyPool.TradeParams(0, 1, 0, 0, bytes("")));
    }
}
