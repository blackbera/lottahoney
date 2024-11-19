// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { LibClone } from "solady/src/utils/LibClone.sol";

import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { BerachainRewardsVault } from "src/pol/rewards/BerachainRewardsVault.sol";
import { BerachainGovernance, InitialGovernorParameters } from "src/gov/BerachainGovernance.sol";
import { TimeLock } from "src/gov/TimeLock.sol";
import "../../gov/GovernanceBase.t.sol";

/// @title POLGasSimulationSimple
/// @dev This contract simulates the Proof of Liquidity (POL) gas consumption and the governance mechanism involved.
/// It integrates with a governance system, simulating real-world operations such as proposal creation, voting,
/// and execution within a blockchain governance framework.
contract POLGasSimulationSimple is GovernanceBaseTest {
    bytes32 internal proof; // Store cryptographic proof
    bytes internal signature; // Signature corresponding to the proof
    uint256 internal signerPrivateKey = 0xabc123; // Private key for simulated signer, for test purposes only
    address internal signer; // Address of the signer

    /// @dev Sets up the environment for each test case. This includes deploying and initializing
    /// governance-related contracts and configuring the initial state required for subsequent tests.
    function setUp() public virtual override {
        // Deploying governance logic via an ERC1967 proxy
        gov = BerachainGovernance(payable(LibClone.deployERC1967(address(new BerachainGovernance()))));
        governance = address(gov);

        // Deploy a new TimelockController instance through an ERC1967 proxy
        timelock = TimeLock(payable(LibClone.deployERC1967(address(new TimeLock()))));

        // Grant necessary roles for the governance to interact with the timelock
        address[] memory proposers = new address[](1);
        proposers[0] = address(governance);
        address[] memory executors = new address[](1);
        executors[0] = address(governance);
        // self administration
        timelock.initialize(12 hours, proposers, executors, address(0));

        // Deploy and initialize POL-related contracts
        deployPOL(address(timelock));
        wbera = new WBERA();
        deployBGTFees(address(timelock));

        // Provide initial tokens for testing
        deal(address(bgt), address(this), 100_000_000_000 ether);
        InitialGovernorParameters memory params = InitialGovernorParameters({
            proposalThreshold: 1e9,
            quorumNumeratorValue: 10,
            votingDelay: uint48(5400),
            votingPeriod: uint32(5400)
        });
        gov.initialize(IVotes(address(bgt)), timelock, params);

        // Delegate tokens to self to allow for governance actions
        bgt.delegate(address(this));

        // Advance time and blocks to simulate real-world passage of time
        vm.warp(100 days);
        vm.roll(100);

        // Setup proposal actions, encoded call data for governance actions
        address[] memory targets = new address[](7);
        targets[0] = address(blockRewardController);
        targets[1] = address(blockRewardController);
        targets[2] = address(blockRewardController);
        targets[3] = address(blockRewardController);
        targets[4] = address(bgt);
        targets[5] = address(beraChef);
        targets[6] = address(bgt);

        bytes[] memory calldatas = new bytes[](7);
        calldatas[0] = abi.encodeCall(BlockRewardController.setRewardRate, (100 ether));
        calldatas[1] = abi.encodeCall(BlockRewardController.setMinBoostedRewardRate, (100 ether));
        calldatas[2] = abi.encodeCall(BlockRewardController.setBoostMultiplier, (3 ether));
        calldatas[3] = abi.encodeCall(BlockRewardController.setRewardConvexity, (0.5 ether));
        calldatas[4] = abi.encodeCall(BGT.whitelistSender, (address(distributor), true));
        calldatas[5] = abi.encodeCall(BeraChef.setCuttingBoardBlockDelay, (0));
        calldatas[6] = abi.encodeCall(BGT.setMinter, (address(blockRewardController)));

        // Create and execute governance proposals
        governanceHelper(targets, calldatas);

        // Setup and manage rewards vaults
        BerachainRewardsVault[] memory vaults = createVaults(1);

        // Configure reward distribution weights
        uint96[] memory weights = new uint96[](1);
        weights[0] = 10_000; // Set weight for the vault
        configureWeights(vaults, weights);

        // Add incentives to the vault
        addIncentives(vaults, 1);

        // Prepare signature verification simulation
        signer = vm.addr(signerPrivateKey);
        proof =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", abi.encodePacked(valPubkey, block.number)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, proof);
        signature = abi.encodePacked(r, s, v);
    }

    /// @dev Tests the gas consumption of POL distribution logic under normal operation conditions
    /// relative to the gas limit of an Arbitrum block.
    // @notice 355396 GAS takes up 1.11% of Arbitrum block gas limit
    function testGasPOLDistribution() public {
        uint256 nextBlock = distributor.getNextActionableBlock();
        validateAndDistribute(proof, signature, abi.encode(valPubkey, nextBlock));
    }

    /// @dev Simulate not yet implemented signature verification function of Prover
    function validateAndDistribute(
        bytes32 _proof,
        bytes memory _signature,
        bytes memory data
    )
        public
        returns (address validatorAddress, uint256 extractedBlockNumber)
    {
        (validatorAddress, extractedBlockNumber) = abi.decode(data, (address, uint256));

        require(ECDSA.recover(_proof, _signature) == signer, "POLGasSimulationSimple: Invalid signature");

        deal(address(bgt), address(bgt).balance + 100 ether); // simulate native token distribution
        bytes32[] memory dummyProof;
        distributor.distributeFor(0, uint64(extractedBlockNumber), 0, valPubkey, dummyProof, dummyProof);

        return (validatorAddress, extractedBlockNumber);
    }
}
