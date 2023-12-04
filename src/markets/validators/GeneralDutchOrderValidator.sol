// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPredyPool} from "../../interfaces/IPredyPool.sol";
import {DecayLib} from "../../libraries/orders/DecayLib.sol";
import {LiquidationLogic} from "../../libraries/logic/LiquidationLogic.sol";

struct GeneralDutchOrderValidationData {
    uint256 baseSqrtPrice;
    uint256 startSlippageTolerance;
    uint256 endSlippageTolerance;
    uint256 startTime;
    uint256 endTime;
}

/**
 * @notice The DutchOrderValidator contract is responsible for validating the dutch auction orders
 */
contract GeneralDutchOrderValidator {
    function validate(int256, int256, bytes memory validationData, IPredyPool.TradeResult memory tradeResult)
        external
        view
    {
        GeneralDutchOrderValidationData memory validationParams =
            abi.decode(validationData, (GeneralDutchOrderValidationData));

        uint256 slippateTolerance = DecayLib.decay(
            validationParams.startSlippageTolerance,
            validationParams.endSlippageTolerance,
            validationParams.startTime,
            validationParams.endTime
        );

        LiquidationLogic.checkPrice(validationParams.baseSqrtPrice, tradeResult, slippateTolerance, true);
    }
}
