// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/markets/validators/GeneralDutchOrderValidator.sol";
import "../../../src/libraries/math/Bps.sol";

contract GeneralDutchOrderValidatorTest is Test {
    GeneralDutchOrderValidator private _generalDutchOrderValidator;

    function setUp() public {
        _generalDutchOrderValidator = new GeneralDutchOrderValidator();
    }

    function testValidate() public {
        GeneralDutchOrderValidationData memory dutchOrderValidationData;

        dutchOrderValidationData.baseSqrtPrice = 2 ** 96;
        dutchOrderValidationData.startSlippageTolerance = Bps.ONE;
        dutchOrderValidationData.endSlippageTolerance = Bps.ONE;
        dutchOrderValidationData.startTime = block.timestamp;
        dutchOrderValidationData.endTime = block.timestamp + 100;

        bytes memory validationData = abi.encode(dutchOrderValidationData);

        IPredyPool.TradeResult memory tradeResult;

        tradeResult.averagePrice = 2 ** 96;
        tradeResult.sqrtPrice = 2 ** 96;

        _generalDutchOrderValidator.validate(0, 0, validationData, tradeResult);
    }
}
