// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./Setup.t.sol";
import "../../../src/libraries/Perp.sol";

contract TestPerpSettleUserBalance is TestPerp {
    function setUp() public override {
        TestPerp.setUp();
    }

    function testSettleUserBalanceWithLastUser() public {
        Perp.updatePosition(
            pairStatus, userStatus, Perp.UpdatePerpParams(100, -100), Perp.UpdateSqrtPerpParams(100, -100)
        );

        pairStatus.sqrtAssetStatus.lastRebalanceTotalSquartAmount = 0;

        pairStatus.sqrtAssetStatus.tickLower = 100;
        pairStatus.sqrtAssetStatus.tickUpper = 200;

        Perp.settleUserBalance(pairStatus, userStatus);

        assertEq(userStatus.rebalanceLastTickLower, 100);
        assertEq(userStatus.rebalanceLastTickUpper, 200);
        assertEq(userStatus.sqrtPerp.baseRebalanceEntryValue, 99);
        assertEq(userStatus.sqrtPerp.quoteRebalanceEntryValue, 99);
    }

    function testSettleUserBalanceReallocated() public {
        Perp.updatePosition(
            pairStatus, userStatus, Perp.UpdatePerpParams(100, -100), Perp.UpdateSqrtPerpParams(100, -100)
        );

        pairStatus.sqrtAssetStatus.lastRebalanceTotalSquartAmount = 50;

        pairStatus.sqrtAssetStatus.tickLower = 100;
        pairStatus.sqrtAssetStatus.tickUpper = 200;

        Perp.settleUserBalance(pairStatus, userStatus);

        assertEq(userStatus.rebalanceLastTickLower, 100);
        assertEq(userStatus.rebalanceLastTickUpper, 200);
        assertEq(userStatus.sqrtPerp.baseRebalanceEntryValue, 98);
        assertEq(userStatus.sqrtPerp.quoteRebalanceEntryValue, 99);
    }
}
