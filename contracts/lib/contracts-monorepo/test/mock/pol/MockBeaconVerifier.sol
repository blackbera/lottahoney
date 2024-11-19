// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract MockBeaconVerifier {
    function verifyExecutionNumber(
        uint64 timestamp,
        uint64 executionNumber,
        bytes32[] calldata executionNumberProof
    )
        external
        view
    {
        // mock to not revert.
    }
    function verifyBeaconBlockProposer(
        uint64 timestamp,
        uint64 proposerIndex,
        bytes calldata proposerPubkey,
        bytes32[] calldata proposerPubkeyProof
    )
        external
        view
    {
        // mock to not revert.
    }
}
