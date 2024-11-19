// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { BerachainRewardsVault } from "src/pol/rewards/BerachainRewardsVault.sol";

import { MockHoney } from "@mock/honey/MockHoney.sol";
import "./POL.t.sol";

/// @dev This test is for simulating the whole system against a mock BeraRoots contract.
abstract contract RootHelperTest is POLTest {
    event BeaconVerifierSet(address indexed beaconVerifier);
    event AdvancedBlock(uint256 blockNum);

    MockHoney internal honey;
    BerachainRewardsVault internal vault;

    // object used to call distributeFor, its a dummy as we are not testing the proof here.
    bytes32[] dummyProof;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual override {
        super.setUp();

        assertEq(address(distributor.beraChef()), address(beraChef));
        assertEq(address(distributor.blockRewardController()), address(blockRewardController));
        assertEq(address(distributor.bgt()), address(bgt));

        vm.startPrank(governance);
        // Set the reward rate to be 100 bgt per block.
        blockRewardController.setRewardRate(100 ether);
        // Set the min boosted reward rate to be 100 bgt per block.
        blockRewardController.setMinBoostedRewardRate(100 ether);

        // Allow the distributor to send BGT.
        bgt.whitelistSender(address(distributor), true);

        // Setup the cutting board and vault for the honey token.
        honey = new MockHoney();
        vault = BerachainRewardsVault(factory.createRewardsVault(address(honey)));

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(address(vault), 10_000);
        beraChef.updateFriendsOfTheChef(address(vault), true);
        beraChef.setDefaultCuttingBoard(IBeraChef.CuttingBoard(1, weights));

        vm.stopPrank();
    }

    function test_SetBeaconVerifier_FailIfZeroAddress() public virtual {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        distributor.setBeaconVerifier(address(0));
    }

    function test_SetBeaconVerifier() public virtual {
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit BeaconVerifierSet(address(1));
        distributor.setBeaconVerifier(address(1));
        assertEq(address(distributor.beaconVerifier()), address(1));
    }

    /// @dev Test resetting the block count.
    function test_ResetCount() public virtual {
        vm.startPrank(governance);
        vm.roll(1);
        // Cannot reset block to a future block
        vm.expectRevert(IPOLErrors.BlockDoesNotExist.selector);
        distributor.resetCount(100);

        // Set block to 10000
        vm.roll(10_000);

        // Cannot reset to a block not in the buffer
        vm.expectRevert(IPOLErrors.BlockNotInBuffer.selector);
        distributor.resetCount(2);

        // Should successfully reset the block count
        uint256 _block = 10_000 - HISTORY_BUFFER_LENGTH + 1;
        distributor.resetCount(_block);
        assertEq(_block, distributor.getNextActionableBlock());
    }

    /// @dev Should fail if attempted to increment out of buffer.
    function test_FailIfNotActionableBlock() public virtual {
        vm.expectRevert(IPOLErrors.NotActionableBlock.selector);
        distributor.distributeFor(0, 2, 0, valPubkey, dummyProof, dummyProof);
    }
}
