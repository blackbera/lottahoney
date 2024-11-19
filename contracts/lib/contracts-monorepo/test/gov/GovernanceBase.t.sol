// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";

import { MockHoney } from "@mock/honey/MockHoney.sol";
import { MockDAI } from "@mock/honey/MockAssets.sol";
import { BerachainRewardsVault } from "src/pol/rewards/BerachainRewardsVault.sol";
import { BerachainGovernance } from "src/gov/BerachainGovernance.sol";
import { TimeLock } from "src/gov/TimeLock.sol";
import { IBeraChef } from "src/pol/interfaces/IBeraChef.sol";
import "../pol/POL.t.sol";

abstract contract GovernanceBaseTest is POLTest {
    BerachainGovernance internal gov;
    TimeLock internal timelock;

    function createVault() internal returns (BerachainRewardsVault vault) {
        // Setup the cutting board and vault for the honey token.
        MockHoney consensusAsset = new MockHoney();

        // The creation of the vault is permissionless.
        vault = BerachainRewardsVault(factory.createRewardsVault(address(consensusAsset)));

        // Update the friends of the chef.
        address[] memory targets = new address[](1);
        targets[0] = address(beraChef);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(BeraChef.updateFriendsOfTheChef, (address(vault), true));

        governanceHelper(targets, calldatas);
    }

    function createVaults(uint256 numVaults) internal returns (BerachainRewardsVault[] memory vaults) {
        vaults = new BerachainRewardsVault[](numVaults);
        for (uint256 i; i < numVaults; ++i) {
            vaults[i] = createVault();
        }
    }

    function addIncentives(BerachainRewardsVault[] memory vaults, uint256 incentivesCount) internal {
        MockDAI[] memory incentives = new MockDAI[](incentivesCount);
        address[] memory targets = new address[](vaults.length * incentivesCount);
        bytes[] memory calldatas = new bytes[](vaults.length * incentivesCount);

        for (uint256 i; i < incentivesCount; ++i) {
            // Create a new USDC token.
            incentives[i] = new MockDAI();
            // Whitelist the USDC token in the vault.
            for (uint256 j; j < vaults.length; ++j) {
                BerachainRewardsVault vault = vaults[j];

                // add incentives for the next 100 blocks.
                uint256 index = i * vaults.length + j;
                targets[index] = address(vault);
                calldatas[index] =
                    abi.encodeCall(BerachainRewardsVault.whitelistIncentiveToken, (address(incentives[i]), 100 ether));
            }
        }
        // Create and execute governance proposals
        governanceHelper(targets, calldatas);

        for (uint256 i; i < incentivesCount; ++i) {
            for (uint256 j; j < vaults.length; ++j) {
                BerachainRewardsVault vault = vaults[j];
                deal(address(incentives[i]), address(this), 100 ether);
                incentives[i].approve(address(vault), 100 ether);
                vault.addIncentive(address(incentives[i]), 100 ether, 1 ether);
            }
        }
    }

    function configureWeights(BerachainRewardsVault[] memory vaults, uint96[] memory percentageNumerators) internal {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](vaults.length);
        for (uint256 i; i < vaults.length; ++i) {
            weights[i] = IBeraChef.Weight(address(vaults[i]), percentageNumerators[i]);
        }
        // Set the weights for the cutting board.
        address[] memory targets = new address[](1);
        targets[0] = address(beraChef);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(BeraChef.setDefaultCuttingBoard, (IBeraChef.CuttingBoard(1, weights)));
        governanceHelper(targets, calldatas);

        vm.prank(operator);
        beraChef.queueNewCuttingBoard(valPubkey, uint64(block.number + 1), weights);
    }

    function normalizeWeights(uint96[] memory weights, uint256 numVaults) internal pure {
        uint96 totalWeight = 0;
        for (uint256 i; i < numVaults; ++i) {
            totalWeight += weights[i];
        }

        // Check if totalWeight is already 10000 to avoid division if not necessary
        if (totalWeight != 10_000) {
            for (uint256 i; i < numVaults; ++i) {
                // Adjust each weight proportionally
                weights[i] = uint96((uint256(weights[i]) * 10_000) / totalWeight);
            }
        }

        // Ensure that the total exactly adds up to 10000 due to integer division adjustments
        uint96 correctedTotal = 0;
        for (uint256 i; i < numVaults; ++i) {
            correctedTotal += weights[i];
        }

        if (correctedTotal != 10_000) {
            // Adjust the last weight to make the sum exactly 10000
            weights[numVaults - 1] = weights[numVaults - 1] + 10_000 - correctedTotal;
        }
    }

    function governanceHelper(address[] memory targets, bytes[] memory calldatas) internal {
        uint256[] memory values = new uint256[](targets.length);

        uint256 proposalId = gov.propose(targets, values, calldatas, "random description");

        uint256 votingStart = gov.proposalSnapshot(proposalId);

        if (block.number < votingStart) {
            vm.roll(votingStart + 1); // move to the block where voting is allowed
        }

        gov.castVote(proposalId, 1);

        // Move time forward to pass the voting period
        vm.roll(gov.proposalDeadline(proposalId) + 1);

        if (gov.state(proposalId) == IGovernor.ProposalState.Succeeded) {
            gov.queue(
                targets,
                values,
                calldatas,
                keccak256("random description") // descriptionHash
            );

            uint256 timelockDelay = timelock.getMinDelay();
            vm.warp(block.timestamp + timelockDelay + 1);

            gov.execute(
                targets,
                values,
                calldatas,
                keccak256("random description") // descriptionHash
            );
        } else {
            revert();
        }
    }
}
