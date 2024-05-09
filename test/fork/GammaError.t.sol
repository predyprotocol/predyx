// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {PredyPool} from "../../src/PredyPool.sol";
import {DataType} from "../../src/libraries/DataType.sol";
import {Perp} from "../../src/libraries/Perp.sol";

interface IProxy {
    function upgradeTo(address newImplementation) external;
}

contract TestFork is Test {
    uint256 internal _arbitrumFork;
    string internal _arbitrumRPCURL = vm.envString("ARBITRUM_RPC_URL");

    PredyPool internal _predyPool = PredyPool(0x9215748657319B17fecb2b5D086A3147BFBC8613);

    address _user = address(0x51B89C499F3038756Eff64a0EF52d753147EAd75);

    function setUp() public virtual {
        _arbitrumFork = vm.createFork(_arbitrumRPCURL);
        vm.selectFork(_arbitrumFork);
        vm.rollFork(204190410);
    }

    function testRiskParam() public {
        vm.startPrank(0x4f071924D66BBC71A5254217893CC7D49938B1c4);
        IProxy(0x9215748657319B17fecb2b5D086A3147BFBC8613).upgradeTo(address(new PredyPool()));
        vm.stopPrank();

        DataType.PairStatus memory pairStatus = _predyPool.getPairStatus(2);

        assertEq(pairStatus.riskParams.riskRatio, 100995049);

        assertEq(pairStatus.riskParams.debtRiskRatio, 0);

        assertEq(pairStatus.riskParams.rangeSize, 600);

        vm.startPrank(0x4b748969Ab77C9d09AE07b4282A151B82F96311B);
        _predyPool.updateAssetRiskParams(2, Perp.AssetRiskParams(100995049, 1000, 600, 300, 1005000, 1016000));
        vm.stopPrank();

        DataType.PairStatus memory pairStatus2 = _predyPool.getPairStatus(2);

        assertEq(pairStatus2.riskParams.riskRatio, 100995049);

        assertEq(pairStatus2.riskParams.debtRiskRatio, 1000);

        assertEq(pairStatus2.riskParams.rangeSize, 600);
        assertEq(pairStatus2.riskParams.rebalanceThreshold, 300);
        assertEq(pairStatus2.riskParams.minSlippage, 1005000);
        assertEq(pairStatus2.riskParams.maxSlippage, 1016000);
    }

    /*
    function testForkGamma() public {
        vm.startPrank(0x4f071924D66BBC71A5254217893CC7D49938B1c4);
        IProxy(0x92027Eb7caa12EC06f9Ba149c9521A1A48921514).upgradeTo(address(new GammaTradeMarketL2()));
        vm.stopPrank();

        IFillerMarket.SettlementParamsV3 memory params = IFillerMarket.SettlementParamsV3(
            address(0x5f1E0379D04f77d221fbFa4c4D6105d097Fd690C),
            hex"82af49447d8a07e3bd95bd0d56f35241523fbab10001f4af88d065e77c8cc2239327c5edb3a432268e5831",
            260291298454934904138,
            252597959584345695149,
            0,
            51288925803928059,
            0
        );

        vm.startPrank(_user);
        _market.executeTradeL2(GammaOrderL2(
            address(0x4b748969Ab77C9d09AE07b4282A151B82F96311B),
            66042084162335774773339711026263175549141763307090288250550116010586506526720,
            0,
            93732087000000000000,
            -5335163887000000,
            50000000,
            4510512677736399603218205,
            bytes32(0x00000000000000000000001e000f4df800000000000000020000000066286cc6),
            bytes32(0x00b4000100001f40000f58e8000f4d3000000000000000000000000066287626),
            0,
            0
        ),
        hex"3c84bd887428512a42d6466b95f72fd71f329a4e38c247576ba85cc490c93553526890ada018953e2edef1be3f7aff3e7d5a57528359f24b928e48944d100b8d1b",
        params);

        vm.stopPrank();
    }

    function testForkGammaAutoHedge() public {
        vm.startPrank(0x4f071924D66BBC71A5254217893CC7D49938B1c4);
        IProxy(0x92027Eb7caa12EC06f9Ba149c9521A1A48921514).upgradeTo(address(new GammaTradeMarketL2()));
        vm.stopPrank();

        IFillerMarket.SettlementParamsV3 memory params = IFillerMarket.SettlementParamsV3(
            address(0x5f1E0379D04f77d221fbFa4c4D6105d097Fd690C),
            hex"82af49447d8a07e3bd95bd0d56f35241523fbab10001f4af88d065e77c8cc2239327c5edb3a432268e5831",
            253105003028066533885,
            245624066977975897416,
            0,
            24936453500302121,
            0
        );

        vm.startPrank(_user);
        _market.autoHedge(15, params);

        vm.stopPrank();
    }
    */
}
