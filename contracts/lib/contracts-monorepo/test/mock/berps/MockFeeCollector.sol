// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

contract MockFeeCollector {
    address public payoutToken;

    constructor(address _payoutToken) {
        payoutToken = _payoutToken;
    }

    function setPayoutToken(address _payoutToken) external {
        payoutToken = _payoutToken;
    }

    function donate(uint256 _amount) external { }
}
