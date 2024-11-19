// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

interface IBeaconDeposit {
    /**
     * @notice Returns the operator address for a validator.
     * @param valPubkey The validator's pubkey.
     * @return operatorAddress the operator address.
     */
    function getOperator(bytes calldata valPubkey) external view returns (address);
}
