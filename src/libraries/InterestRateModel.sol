// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

library InterestRateModel {
    struct IRMParams {
        uint256 baseRate;
        uint256 kinkRate;
        uint256 slope1;
        uint256 slope2;
    }

    uint256 private constant ONE = 1e18;

    function calculateInterestRate(IRMParams memory _irmParams, uint256 _utilizationRatio)
        internal
        pure
        returns (uint256)
    {
        uint256 ir = _irmParams.baseRate;

        if (_utilizationRatio <= _irmParams.kinkRate) {
            ir += (_utilizationRatio * _irmParams.slope1) / ONE;
        } else {
            ir += (_irmParams.kinkRate * _irmParams.slope1) / ONE;
            ir += (_irmParams.slope2 * (_utilizationRatio - _irmParams.kinkRate)) / ONE;
        }

        return ir;
    }
}
