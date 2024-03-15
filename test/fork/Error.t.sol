// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/libraries/orders/OrderInfoLib.sol";
import "../../src/lens/PerpMarketQuoter.sol";
import "../../src/markets/perp/PerpMarket.sol";
import "../../src/markets/spot/SpotMarket.sol";

contract TestFork is Test {
    uint256 internal _arbitrumFork;
    string internal _arbitrumRPCURL = vm.envString("ARBITRUM_RPC_URL");

    //PerpMarketQuoter internal _quoter = PerpMarketQuoter(0xC78480283D9895c24b7bd60381EEBF3DB75734d1);
    PerpMarket internal _market = PerpMarket(0x02C9Ad1Aa219BCF221C3f915c45595f1d24928a1);
    //SpotMarket internal _market = SpotMarket(0x4ef750BE34bB35963bCd8bFC94468df4DF495781);
    address _user = address(0x51B89C499F3038756Eff64a0EF52d753147EAd75);

    function setUp() public virtual {
        _arbitrumFork = vm.createFork(_arbitrumRPCURL);
        vm.selectFork(_arbitrumFork);
        vm.rollFork(181227100);
    }

    function testForkQuote() public {
        /*
        IFillerMarket.SettlementParams memory params = IFillerMarket.SettlementParams(
            address(0x5f1E0379D04f77d221fbFa4c4D6105d097Fd690C),
            hex"82af49447d8a07e3bd95bd0d56f35241523fbab10001F4ff970a61a04b1ca14834a43f5de4533ebddb5cc8000064af88d065e77c8cc2239327c5edb3a432268e5831",
            5766796755,
            0,
            568157
        );

        _quoter.quoteExecuteOrder(
            PerpOrder(
                OrderInfo(
                    address(0x02C9Ad1Aa219BCF221C3f915c45595f1d24928a1),
                    address(0x4b748969Ab77C9d09AE07b4282A151B82F96311B),
                    4074370768596132808262492750746597821864139596042,
                    1707333675
                ),
                2,
                address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831),
                1152921504606846976,
                -227902080,
                0,
                0,
                0,
                10,
                address(0xAAA65f9851bC59DF7688bD3163738f00496f802d),
                bytes(
                    hex"0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a5c05a4d1c99591c30000000000000000000000000000000000000000000000000000000000000000"
                )
            ),
            IFillerMarket.SettlementParams(0, 400000, items),
            _user
        );

        vm.startPrank(_user);
        _market.executeOrderV2(
            PerpOrderV2(
                0x4b748969Ab77C9d09AE07b4282A151B82F96311B,
                4074370768596132808262492750746597821864139596055,
                bytes32(0x0000000000000000000000000000000a00000000000000020000000065ceed49),
                2000000000000000000,
                0,
                address(0x1Df9b0A328A41E2b01C439fF9C90C481B3170c5e),
                hex"00000000000000000000000000000000000000000000000c452745acbdc6248100000000000000000000000000000000000000000000000c452745acbdc6248100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
            ),
            hex"b7e54f82fc5bcb2f300f207e71fb109b9927c06d00d6b8a3c4dbd9ceeca2e5b853edd944fbca34ab0484a9b486ac58291e81b55269462e91178689e145f710411b",
            params
        );
        vm.stopPrank();
        */
    }
}
