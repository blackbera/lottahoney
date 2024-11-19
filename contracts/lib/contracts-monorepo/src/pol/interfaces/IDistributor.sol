// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import { IPOLErrors } from "./IPOLErrors.sol";

/// @notice Interface of the Distributor contract.
interface IDistributor is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event BeaconVerifierSet(address indexed beaconVerifier);

    event Distributed(bytes indexed valPubkey, uint256 indexed blockNumber, address indexed receiver, uint256 amount);

    /**
     * @notice Distribute the rewards to the cutting board receivers.
     * @dev Permissionless function to distribute rewards by providing the necessary Merkle proofs.
     * Reverts if the Merkle proofs are invalid.
     * @param timestamp The timestamp of the beacon block.
     * @param blockNumber The block number to distribute the rewards for.
     * @param proposerIndex The Validator Index of the proposer.
     * @param pubkey The pubkey of the proposer.
     * @param pubkeyProof The Merkle proof of the proposer pubkey.
     * @param blockNumberProof The Merkle proof of the block/execution number.
     */
    function distributeFor(
        uint64 timestamp,
        uint64 blockNumber,
        uint64 proposerIndex,
        bytes calldata pubkey,
        bytes32[] calldata pubkeyProof,
        bytes32[] calldata blockNumberProof
    )
        external;
}
