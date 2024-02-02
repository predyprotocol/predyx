// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/libraries/orders/OrderInfoLib.sol";
import "../../src/lens/PerpMarketQuoter.sol";

contract TestFork is Test {
    uint256 internal _arbitrumFork;
    string internal _arbitrumRPCURL = vm.envString("ARBITRUM_RPC_URL");

    PerpMarketQuoter internal _quoter = PerpMarketQuoter(0xdAedaA23f1010d742C2d42922bBA15Ba3378AA06);
    address _user = address(0x51B89C499F3038756Eff64a0EF52d753147EAd75);

    function setUp() public virtual {
        _arbitrumFork = vm.createFork(_arbitrumRPCURL);
        vm.selectFork(_arbitrumFork);
        vm.rollFork(175268733);
    }

    function testForkQuote() public {
        IFillerMarket.SettlementParamsItem[] memory items = new IFillerMarket.SettlementParamsItem[](1);
        items[0] = IFillerMarket.SettlementParamsItem(
            address(0x5f1E0379D04f77d221fbFa4c4D6105d097Fd690C),
            hex"82af49447d8a07e3bd95bd0d56f35241523fbab10001f4ff970a61a04b1ca14834a43f5de4533ebddb5cc8",
            2246649,
            0
        );

        vm.expectRevert();
        _quoter.quoteExecuteOrder(
            PerpOrder(
                OrderInfo(
                    address(0x02C9Ad1Aa219BCF221C3f915c45595f1d24928a1),
                    address(0x4b748969Ab77C9d09AE07b4282A151B82F96311B),
                    9,
                    1709094411
                ),
                1,
                address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8),
                -1000000000000000,
                -380602,
                0,
                0,
                0,
                2,
                address(0x1Df9b0A328A41E2b01C439fF9C90C481B3170c5e),
                bytes(
                    hex"000000000000000000000000000000000000000000000009aa85ad6e2f5b308d000000000000000000000000000000000000000000000009aa85ad6e2f5b308d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
                )
            ),
            IFillerMarket.SettlementParams(0, 400000, items),
            _user
        );
    }
}
