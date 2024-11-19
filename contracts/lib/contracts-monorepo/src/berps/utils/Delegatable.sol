// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IDelegatable } from "../interfaces/utils/IDelegatable.sol";

import { Utils } from "../../libraries/Utils.sol";

/// @title Delegatable
/// @notice Allows a user to delegate a call to another address.
/// @dev Supports payable functions.
abstract contract Delegatable is IDelegatable {
    using Utils for bytes;

    mapping(address => address) public delegations;
    address private senderOverride;

    function setDelegate(address delegate) external {
        require(tx.origin == msg.sender, "NO_CONTRACT");

        delegations[msg.sender] = delegate;
    }

    function removeDelegate() external {
        delegations[msg.sender] = address(0);
    }

    function delegatedAction(
        address trader,
        bytes calldata call_data
    )
        external
        payable
        override
        returns (bytes memory)
    {
        require(delegations[trader] == msg.sender, "DELEGATE_NOT_APPROVED");

        senderOverride = trader;
        (bool success, bytes memory result) = address(this).delegatecall(call_data);
        if (!success) result.revertFor();

        senderOverride = address(0);

        return result;
    }

    function _msgSender() public view returns (address) {
        if (senderOverride == address(0)) {
            return msg.sender;
        } else {
            return senderOverride;
        }
    }

    receive() external payable virtual { }

    /// @inheritdoc IDelegatable
    function refundValue() external payable virtual {
        if (address(this).balance > 0) SafeTransferLib.safeTransferETH(msg.sender, address(this).balance);
    }
}
