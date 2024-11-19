// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./POLGasSim.t.sol";

contract POLE2EFuzz is POLGasSimulationSimple {
    event RewardAdded(uint256 bgtEmitted);

    function setUp() public override {
        super.setUp();
        testGasPOLDistribution(); // advance to block > 0 to be able to use queued cutting board
    }

    function testFuzzDistribution(uint96[] memory weights, uint256 numVaults, uint256 incentivesCount) public {
        // Bound the number of vaults and incentives count within valid ranges
        numVaults = bound(numVaults, 1, 10);
        incentivesCount = bound(incentivesCount, 1, 3);

        // Ensure the weights array has the same number of elements as the number of vaults
        weights = new uint96[](numVaults); // Reinitialize weights array to match numVaults
        for (uint256 i; i < numVaults; ++i) {
            weights[i] = uint96(bound(weights[i], 1, 10_000)); // Ensure each weight is within a valid range
        }

        normalizeWeights(weights, numVaults); // Normalize weights
        BerachainRewardsVault[] memory vaults = setUpFuzz(weights, numVaults, incentivesCount); // Setup the
            // environment with fuzzed data

        // Total rewards for the block are set by super.setUp() to 100 ether
        uint256 totalRewards = 100 ether;

        // Calculate expected rewards for each vault and expect the RewardAdded event
        for (uint256 i; i < numVaults; ++i) {
            uint256 expectedReward = (totalRewards * weights[i]) / 10_000;
            vm.expectEmit(true, true, true, true, address(vaults[i]));
            emit RewardAdded(expectedReward);
        }

        deal(address(bgt), address(bgt).balance + 100 ether); // simulate native token distribution
        bytes32[] memory dummyProof;
        distributor.distributeFor(
            0, uint64(distributor.getNextActionableBlock()), 0, valPubkey, dummyProof, dummyProof
        );
        // Verification
        verifyWeights(numVaults, weights);
    }

    function verifyWeights(uint256 numVaults, uint96[] memory weights) internal view {
        IBeraChef.CuttingBoard memory cb = beraChef.getActiveCuttingBoard(valPubkey);
        assertEq(cb.weights.length, numVaults, "Mismatch in number of weights");
        for (uint256 i; i < numVaults; ++i) {
            assertEq(cb.weights[i].percentageNumerator, weights[i], "Mismatch in weight configuration");
        }
    }

    function setUpFuzz(
        uint96[] memory weights,
        uint256 numVaults,
        uint256 incentivesCount
    )
        internal
        returns (BerachainRewardsVault[] memory vaults)
    {
        vaults = createVaults(numVaults);
        configureWeights(vaults, weights);
        addIncentives(vaults, incentivesCount);
        vm.roll(block.number + 1); // Ensure new cutting board is active
    }
}
