// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IDelegatable {
    function delegatedAction(address trader, bytes calldata data) external payable returns (bytes memory);

    /// @notice Indicates that this contract can receive value.
    receive() external payable;

    /// @notice Refunds any value held by this contract to the `msg.sender`.
    /// @dev Useful for bundling with operations that require sending a value.
    /// @dev Should NOT be called by any other contracts because of low-level call(s).
    /// @dev Sends the value to `msg.sender` and NOT the sender's override address.
    function refundValue() external payable;
}
