// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./Constants.sol";

library PremiumCurveModel {
    /**
     * @notice Calculates premium curve
     * 0 {ur <= 0.1}
     * 1.6 * (UR-0.1)^2 {0.1 < ur}
     * @param _utilization utilization ratio scaled by 1e18
     * @return spread parameter scaled by 1e3
     */
    function calculatePremiumCurve(uint256 _utilization) internal pure returns (uint256) {
        if (_utilization <= Constants.SQUART_KINK_UR) {
            return 0;
        }

        uint256 b = (_utilization - Constants.SQUART_KINK_UR);

        return (1600 * b * b / Constants.ONE) / Constants.ONE;
    }
}
