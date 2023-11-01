// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {IFillerMarket} from "../../src/interfaces/IFillerMarket.sol";

contract TestAaveMarketDepositToFillerPool is TestAavePerp {
    uint256 fillerPoolId;

    uint256 fromPrivateKey;
    address from;

    function setUp() public override {
        TestAavePerp.setUp();

        fromPrivateKey = 0x12340003;
        from = vm.addr(fromPrivateKey);

        fillerPoolId = pairId;
    }

    function testCannotDepositToFillerPool() public {
        vm.expectRevert();
        _aavePerp.depositToInsurancePool(fillerPoolId, 0);
    }

    function testCannotDepositToFillerPoolIfCallerIsNotFiller() public {
        vm.startPrank(from1);

        vm.expectRevert(IFillerMarket.CallerIsNotFiller.selector);
        _aavePerp.depositToInsurancePool(fillerPoolId, 1000000);

        vm.stopPrank();
    }

    function testCannotDepositToFillerPoolIfBalanceIsZero() public {
        vm.startPrank(from);

        uint256 newFillerPoolId = _aavePerp.addPair(address(_usdc), address(_weth));

        vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
        _aavePerp.depositToInsurancePool(newFillerPoolId, 1000000);

        vm.stopPrank();
    }

    function testDepositToFillerPool(uint256 marginAmount) public {
        marginAmount = bound(marginAmount, 1, 1e6);

        _aavePerp.depositToInsurancePool(fillerPoolId, marginAmount);

        (,, int256 fillerMarginAmount,,,,,,) = _aavePerp.insurancePools(fillerPoolId);

        assertEq(fillerMarginAmount, int256(marginAmount));
    }
}
