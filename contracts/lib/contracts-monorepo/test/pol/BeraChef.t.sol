// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { IBeraChef, IPOLErrors } from "src/pol/interfaces/IBeraChef.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { BerachainRewardsVault } from "src/pol/rewards/BerachainRewardsVault.sol";

import { POLTest, Vm } from "./POL.t.sol";
import { MockHoney } from "@mock/honey/MockHoney.sol";

contract BeraChefTest is POLTest {
    address internal receiver;
    address internal receiver2;
    address internal stakeTokenVault;
    address internal stakeTokenVault2;

    /// @dev A function invoked before each test case is run.
    function setUp() public override {
        super.setUp();

        stakeTokenVault = address(new MockHoney());
        stakeTokenVault2 = address(new MockHoney());

        vm.startPrank(governance);
        receiver = factory.createRewardsVault(address(stakeTokenVault));
        receiver2 = factory.createRewardsVault(address(stakeTokenVault2));

        // Become frens with the chef.
        beraChef.updateFriendsOfTheChef(receiver, true);
        beraChef.updateFriendsOfTheChef(receiver2, true);
        vm.stopPrank();
    }

    /* Admin functions */

    /// @dev Ensure that the contract is owned by the governance.
    function test_OwnerIsGovernance() public view {
        assertEq(beraChef.owner(), governance);
    }

    /// @dev Should fail if not the owner
    function test_FailIfNotOwner() public {
        vm.expectRevert();
        beraChef.transferOwnership(address(1));

        vm.expectRevert();
        beraChef.setMaxNumWeightsPerCuttingBoard(255);

        vm.expectRevert();
        beraChef.setCuttingBoardBlockDelay(255);

        vm.expectRevert();
        beraChef.updateFriendsOfTheChef(receiver, true);

        vm.expectRevert();
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(governance, 10_000);
        beraChef.setDefaultCuttingBoard(IBeraChef.CuttingBoard(0, weights));

        address newImpl = address(new BeraChef());
        vm.expectRevert();
        beraChef.upgradeToAndCall(newImpl, bytes(""));
    }

    /// @dev Should upgrade to a new implementation
    function test_UpgradeTo() public {
        address newImpl = address(new BeraChef());
        vm.expectEmit(true, true, true, true);
        emit ERC1967Utils.Upgraded(newImpl);
        vm.prank(governance);
        beraChef.upgradeToAndCall(newImpl, bytes(""));
        assertEq(vm.load(address(beraChef), ERC1967Utils.IMPLEMENTATION_SLOT), bytes32(uint256(uint160(newImpl))));
    }

    /// @dev Should fail if initialize again
    function test_FailIfInitializeAgain() public {
        vm.expectRevert();
        beraChef.initialize(address(distributor), address(factory), address(governance), beaconDepositContract, 1);
    }

    function test_SetMaxNumWeightsPerCuttingBoard_FailWithZero() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.MaxNumWeightsPerCuttingBoardIsZero.selector);
        beraChef.setMaxNumWeightsPerCuttingBoard(0);
    }

    /// @dev Should set the max number of weights per cutting board
    function test_SetMaxNumWeightsPerCuttingBoard() public {
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.MaxNumWeightsPerCuttingBoardSet(255);
        vm.prank(governance);
        beraChef.setMaxNumWeightsPerCuttingBoard(255);
        assertEq(beraChef.maxNumWeightsPerCuttingBoard(), 255);
    }

    /// @dev Should set the max number of weights per cutting board
    function testFuzz_SetMaxNumWeightsPerCuttingBoard(uint8 seed) public {
        seed = uint8(bound(seed, 1, type(uint8).max));
        vm.prank(governance);
        beraChef.setMaxNumWeightsPerCuttingBoard(seed);
        assertEq(beraChef.maxNumWeightsPerCuttingBoard(), seed);
    }

    /// @dev Should set the cutting board block delay
    function test_SetCuttingBoardBlockDelay() public {
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.CuttingBoardBlockDelaySet(255);
        vm.prank(governance);
        beraChef.setCuttingBoardBlockDelay(255);
        assertEq(beraChef.cuttingBoardBlockDelay(), 255);
    }

    /// @dev Should set the cutting board block delay
    function testFuzz_SetCuttingBoardBlockDelay(uint64 seed) public {
        uint64 maxDelay = beraChef.MAX_CUTTING_BOARD_BLOCK_DELAY();
        seed = uint64(bound(seed, 0, maxDelay));
        vm.prank(governance);
        beraChef.setCuttingBoardBlockDelay(seed);
        assertEq(beraChef.cuttingBoardBlockDelay(), seed);
    }

    function testFuzz_SetCuttingBoardBlockDelay_FailsIfDelayTooLarge(uint64 seed) public {
        uint64 maxDelay = beraChef.MAX_CUTTING_BOARD_BLOCK_DELAY();
        seed = uint64(bound(seed, maxDelay + 1, type(uint64).max));
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.CuttingBoardBlockDelayTooLarge.selector);
        beraChef.setCuttingBoardBlockDelay(seed);
    }

    /// @dev Should update the friends of the chef
    function test_UpdateFriendsOfTheChef() public {
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.FriendsOfTheChefUpdated(receiver, true);
        vm.prank(governance);
        beraChef.updateFriendsOfTheChef(receiver, true);
        assertTrue(beraChef.isFriendOfTheChef(receiver));
    }

    function testFuzz_FailUpdateFriendsOfChefNotRegistered() public {
        address recevier3 = address(new BerachainRewardsVault());
        vm.startPrank(governance);
        vm.expectRevert(IPOLErrors.NotFactoryVault.selector);
        beraChef.updateFriendsOfTheChef(recevier3, true);
    }

    /// @dev Should revert because invalidating the default cutting board
    function test_FailIfRemovingAFriendInvalidatesDefaultCuttingBoard() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        weights[0] = IBeraChef.Weight(receiver, 5000);
        weights[1] = IBeraChef.Weight(receiver2, 5000);
        vm.startPrank(governance);
        beraChef.setDefaultCuttingBoard(IBeraChef.CuttingBoard(0, weights));
        vm.expectRevert(IPOLErrors.InvalidCuttingBoardWeights.selector);
        beraChef.updateFriendsOfTheChef(receiver, false);
    }

    function test_EditDefaultCuttingBoardBeforeRemoveAFriend() public {
        address stakeTokenVault3 = address(new MockHoney());

        vm.startPrank(governance);
        address receiver3 = factory.createRewardsVault(address(stakeTokenVault3));

        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        vm.startPrank(governance);
        beraChef.updateFriendsOfTheChef(receiver3, true); // Set receiver3 as friend

        // Set default cutting board with receiver and receiver2
        test_FailIfRemovingAFriendInvalidatesDefaultCuttingBoard();

        weights[0] = IBeraChef.Weight(receiver2, 5000);
        weights[1] = IBeraChef.Weight(receiver3, 5000);
        beraChef.setDefaultCuttingBoard(IBeraChef.CuttingBoard(0, weights));

        beraChef.updateFriendsOfTheChef(receiver, false);
        assertFalse(beraChef.isFriendOfTheChef(receiver));
    }

    /// @dev Should update the friends of the chef
    function testFuzz_UpdateFriendsOfTheChef(bool isFriend) public {
        vm.prank(governance);
        beraChef.updateFriendsOfTheChef(receiver, isFriend);
        assertEq(beraChef.isFriendOfTheChef(receiver), isFriend);
    }

    /// @dev Should set the default cutting board
    function test_SetDefaultCuttingBoard() public {
        vm.prank(governance);
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver2, 10_000);

        vm.expectEmit(true, true, true, true);
        emit IBeraChef.SetDefaultCuttingBoard(IBeraChef.CuttingBoard(1, weights));
        beraChef.setDefaultCuttingBoard(IBeraChef.CuttingBoard(1, weights));

        IBeraChef.CuttingBoard memory cb = beraChef.getDefaultCuttingBoard();
        assertEq(cb.startBlock, 1);
        assertEq(cb.weights.length, 1);
        assertEq(cb.weights[0].receiver, receiver2);
        assertEq(cb.weights[0].percentageNumerator, 10_000);
        assertTrue(beraChef.isReady());
    }

    /* Queueing a new cutting board */

    /// @dev Should fail if the new cutting board is not in the future
    function test_FailIfTheNewCuttingBoardIsNotInTheFuture() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver, 10_000);
        vm.prank(operator);
        vm.expectRevert(IPOLErrors.InvalidStartBlock.selector);
        beraChef.queueNewCuttingBoard(valPubkey, uint64(block.number), weights);
    }

    /// @dev Should fail if the new cutting board has too many weights
    function test_FailIfTheNewCuttingBoardHasTooManyWeights() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1000);
        for (uint256 i; i < 1000; ++i) {
            weights[i] = IBeraChef.Weight(receiver, 10);
        }
        vm.prank(operator);
        vm.expectRevert(IPOLErrors.TooManyWeights.selector);
        beraChef.queueNewCuttingBoard(valPubkey, uint64(block.number + 1), weights);
    }

    /// @dev Should fail if not friends with the chef
    function test_FailIfNotFriendsWithTheChef() public {
        vm.prank(governance);
        beraChef.updateFriendsOfTheChef(receiver, false);
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver, 10_000);
        vm.prank(operator);
        vm.expectRevert(IPOLErrors.NotFriendOfTheChef.selector);
        beraChef.queueNewCuttingBoard(valPubkey, uint64(block.number + 1), weights);
    }

    /// @dev Should fail if cutting board weights don't add up to 100%
    function test_FailIfInvalidCuttingBoardWeights() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver, 5000);
        vm.prank(operator);
        vm.expectRevert(IPOLErrors.InvalidCuttingBoardWeights.selector);
        beraChef.queueNewCuttingBoard(valPubkey, uint64(block.number + 1), weights);
    }

    /// @dev Should queue a new cutting board
    function test_QueueANewCuttingBoard() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver, 10_000);
        uint64 startBlock = uint64(block.number + 2);
        vm.prank(operator);
        beraChef.queueNewCuttingBoard(valPubkey, startBlock, weights);

        IBeraChef.CuttingBoard memory cb = beraChef.getQueuedCuttingBoard(valPubkey);
        assertEq(cb.startBlock, startBlock);
        assertEq(cb.weights.length, 1);
        assertEq(cb.weights[0].receiver, receiver);
        assertEq(cb.weights[0].percentageNumerator, 10_000);
    }

    /// @dev Should succeed even if there exists a queued cutting board
    function test_QueuedCuttingBoardExists() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver, 10_000);
        vm.startPrank(operator);
        // queue a new cutting board 10000 blocks in the future
        beraChef.queueNewCuttingBoard(valPubkey, uint64(block.number + 10_000), weights);
        // override another cutting board
        beraChef.queueNewCuttingBoard(valPubkey, uint64(block.number + 2), weights);
        // ensure that the queued cutting board is now the 2nd one
        IBeraChef.CuttingBoard memory cb = beraChef.getQueuedCuttingBoard(valPubkey);
        assertEq(cb.startBlock, uint64(block.number + 2));
    }

    /// @dev Should queue a new cutting board with multiple weights
    function test_QueueANewCuttingBoardWithMultipleWeights() public {
        vm.prank(governance);
        beraChef.updateFriendsOfTheChef(receiver2, true);

        // queue a new cutting board with multiple weights
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
        weights[0] = IBeraChef.Weight(receiver, 3000);
        weights[1] = IBeraChef.Weight(receiver2, 7000);
        uint64 startBlock = uint64(block.number + 2);
        vm.prank(operator);
        beraChef.queueNewCuttingBoard(valPubkey, startBlock, weights);

        // ensure that the queued cutting board is set correctly
        IBeraChef.CuttingBoard memory cb = beraChef.getQueuedCuttingBoard(valPubkey);
        assertEq(cb.startBlock, startBlock);
        assertEq(cb.weights.length, 2);
        assertEq(cb.weights[0].receiver, receiver);
        assertEq(cb.weights[0].percentageNumerator, 3000);
        assertEq(cb.weights[1].receiver, receiver2);
        assertEq(cb.weights[1].percentageNumerator, 7000);
    }

    /// @dev Should queue a new cutting board
    // TODO: Fuzz test
    function testFuzz_QueueANewCuttingBoard(uint32 seed) public { }

    // TODO: Invariant test
    // function invariant_test() public { }

    /* Activating a cutting board */

    /// @dev Should fail if the caller is not the distribution contract
    function test_FailIfCallerNotDistributor() public {
        vm.expectRevert(IPOLErrors.NotDistributor.selector);
        beraChef.activateReadyQueuedCuttingBoard(valPubkey, block.number);
    }

    /// @dev Should fail if the cutting board is not queued
    function test_ReturnsIfTheCuttingBoardIsNotQueued() public {
        vm.recordLogs();
        vm.prank(address(distributor));
        beraChef.activateReadyQueuedCuttingBoard(valPubkey, block.number);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // ensure that no event was emitted
        assertEq(entries.length, 0);
    }

    /// @dev Should fail if start block is greater than current block
    function test_ReturnsfStartBlockGreaterThanCurrentBlock() public {
        test_QueueANewCuttingBoard();
        assertFalse(beraChef.isQueuedCuttingBoardReady(valPubkey, block.number));
        vm.recordLogs();
        vm.prank(address(distributor));
        beraChef.activateReadyQueuedCuttingBoard(valPubkey, block.number);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // ensure that no event was emitted
        assertEq(entries.length, 0);
    }

    /// @dev Should activate a cutting board
    function test_ActivateACuttingBoard() public {
        // queue and activate a new cutting board
        test_QueueANewCuttingBoard();
        assertFalse(beraChef.isQueuedCuttingBoardReady(valPubkey, block.number));
        IBeraChef.CuttingBoard memory cb = beraChef.getQueuedCuttingBoard(valPubkey);
        uint64 startBlock = uint64(block.number + 2);

        vm.roll(startBlock);
        assertTrue(beraChef.isQueuedCuttingBoardReady(valPubkey, block.number));
        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBeraChef.ActivateCuttingBoard(valPubkey, startBlock, cb.weights);
        beraChef.activateReadyQueuedCuttingBoard(valPubkey, block.number);
        assertFalse(beraChef.isQueuedCuttingBoardReady(valPubkey, block.number));

        // ensure that the active cutting board is set correctly
        cb = beraChef.getActiveCuttingBoard(valPubkey);
        assertEq(cb.startBlock, startBlock);
        assertEq(cb.weights.length, 1);
        assertEq(cb.weights[0].receiver, receiver);
        assertEq(cb.weights[0].percentageNumerator, 10_000);
    }

    /// @dev Should delete the queued cutting board after activation
    function test_DeleteQueuedCuttingBoardAfterActivation() public {
        // queue a new cutting board
        test_QueueANewCuttingBoardWithMultipleWeights();

        // activate the queued cutting board
        uint64 startBlock = uint64(block.number + 2);
        vm.roll(startBlock);
        vm.prank(address(distributor));
        beraChef.activateReadyQueuedCuttingBoard(valPubkey, block.number);

        // ensure that the queued cutting board is deleted
        IBeraChef.CuttingBoard memory cb = beraChef.getQueuedCuttingBoard(valPubkey);
        assertEq(cb.startBlock, 0);
        assertEq(cb.weights.length, 0);
    }

    /* Getters */

    /// @dev Should return the active cutting board
    function test_GetActiveCuttingBoard() public {
        // ensure that the active cutting board is empty
        IBeraChef.CuttingBoard memory cb = beraChef.getActiveCuttingBoard(valPubkey);
        assertEq(cb.startBlock, 0);
        assertEq(cb.weights.length, 0);

        // queue and activate a new cutting board
        test_ActivateACuttingBoard();
    }

    /// @dev Should return the default cutting board
    function test_GetActiveCuttingBoardReturnsDefaultCuttingBoard() public {
        address stakeTokenVault3 = address(new MockHoney());
        test_GetActiveCuttingBoard();

        // unfriend the receiver
        vm.startPrank(governance);
        beraChef.updateFriendsOfTheChef(receiver, false);
        address receiver3 = factory.createRewardsVault(address(stakeTokenVault3));

        // set default cutting board
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(receiver3, 10_000);
        beraChef.updateFriendsOfTheChef(receiver3, true);
        beraChef.setDefaultCuttingBoard(IBeraChef.CuttingBoard(1, weights));

        // ensure that the default cutting board is set correctly
        IBeraChef.CuttingBoard memory cb = beraChef.getActiveCuttingBoard(valPubkey);
        assertEq(cb.startBlock, 1);
        assertEq(cb.weights.length, 1);
        assertEq(cb.weights[0].receiver, receiver3);
        assertEq(cb.weights[0].percentageNumerator, 10_000);
    }

    function test_GetSetActiveCuttingBoard() public {
        //set default cutting board
        test_SetDefaultCuttingBoard();
        // ensure that the set active cutting board is empty if none is set
        IBeraChef.CuttingBoard memory cb = beraChef.getSetActiveCuttingBoard(valPubkey);
        assertEq(cb.startBlock, 0);
        assertEq(cb.weights.length, 0);

        // queue and activate a new cutting board
        test_ActivateACuttingBoard();

        vm.prank(governance);
        // remove the receiver from the friends of the chef
        beraChef.updateFriendsOfTheChef(receiver, false);

        // getActiveCuttingBoard should return the default cutting board as `receiver` is not a friend of the chef
        cb = beraChef.getActiveCuttingBoard(valPubkey);
        assertEq(cb.weights.length, 1);
        assertEq(cb.weights[0].receiver, receiver2);
        assertEq(cb.weights[0].percentageNumerator, 10_000);

        // getSetActiveCuttingBoard should return the `actual` active cutting board set by validator
        cb = beraChef.getSetActiveCuttingBoard(valPubkey);
        assertEq(cb.weights.length, 1);
        assertEq(cb.weights[0].receiver, receiver);
        assertEq(cb.weights[0].percentageNumerator, 10_000);
    }
}
