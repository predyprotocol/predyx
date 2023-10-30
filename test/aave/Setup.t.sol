// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {Pool} from "../../lib/aave-v3-core/contracts/protocol/pool/Pool.sol";
import {IPoolAddressesProvider} from '../../lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol';

contract TestAavePerp {
    function setUp() public virtual {
        // Pool pool = new Pool(IPoolAddressesProvider(address(0)));
    }
}
