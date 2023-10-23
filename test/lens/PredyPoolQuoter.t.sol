// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import "../../src/lens/PredyPoolQuoter.sol";
import "../../src/settlements/RevertSettlement.sol";

contract TestPredyPoolQuoter is TestLens {
    PredyPoolQuoter _quoter;

    function setUp() public override {
        TestLens.setUp();

        RevertSettlement revertSettlement = new RevertSettlement(predyPool);

        _quoter = new PredyPoolQuoter(predyPool, address(revertSettlement));

        predyPool.createVault(1);
    }

    function testQuotePairStatus() public {
        Perp.PairStatus memory pairStatus = _quoter.quotePairStatus(1);

        assertEq(pairStatus.id, 1);
    }

    /*
    function testQuoteVaultStatus() public {
        IPredyPool.VaultStatus memory vaultStatus = _quoter.quoteVaultStatus(1);

        assertEq(vaultStatus.id, 1);
    }
    */

    function testQuoteBaseAmountDeltaFails() public {
        vm.expectRevert(IPredyPool.InvalidPairId.selector);
        _quoter.quoteBaseAmountDelta(IPredyPool.TradeParams(0, 1, 0, 0, bytes("")));
    }
}
