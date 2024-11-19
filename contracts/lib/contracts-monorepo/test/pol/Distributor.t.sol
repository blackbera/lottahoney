// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { IBeraChef } from "src/pol/interfaces/IBeraChef.sol";
import { IBGT } from "src/pol/interfaces/IBGT.sol";
import { IBlockRewardController } from "src/pol/interfaces/IBlockRewardController.sol";
import { IDistributor } from "src/pol/interfaces/IDistributor.sol";
import { IPOLErrors } from "src/pol/interfaces/IPOLErrors.sol";
import { BeraChef } from "src/pol/rewards/BeraChef.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";
import { BerachainRewardsVault } from "src/pol/rewards/BerachainRewardsVault.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { RootHelperTest } from "./RootHelper.t.sol";
import { MockHoney } from "@mock/honey/MockHoney.sol";

contract DistributorTest is RootHelperTest {
    address internal manager = makeAddr("manager");
    bytes32 internal defaultAdminRole;
    bytes32 internal managerRole;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual override {
        super.setUp();
        defaultAdminRole = distributor.DEFAULT_ADMIN_ROLE();
        managerRole = distributor.MANAGER_ROLE();

        vm.prank(governance);
        distributor.grantRole(managerRole, manager);
    }

    /// @dev Ensure that the contract is owned by the governance.
    function test_OwnerIsGovernance() public virtual {
        assert(distributor.hasRole(defaultAdminRole, governance));
    }

    /// @dev Should fail if not the owner
    function test_FailIfNotOwner() public virtual {
        vm.expectRevert();
        distributor.revokeRole(defaultAdminRole, governance);

        address rnd = makeAddr("address");
        vm.expectRevert();
        distributor.grantRole(managerRole, rnd);

        address newImpl = address(new Distributor());
        vm.expectRevert();
        distributor.upgradeToAndCall(newImpl, bytes(""));

        vm.expectRevert();
        distributor.setBeaconVerifier(address(1));
    }

    /// @dev Should fail if not the manager
    function test_FailIfNotManager() public virtual {
        vm.expectRevert();
        distributor.resetCount(1);
    }

    function test_CanResetIfManager() public virtual {
        vm.prank(manager);
        distributor.resetCount(1);
    }

    /// @dev Test resetting the block count.
    function test_ResetCount() public virtual override {
        vm.startPrank(manager);
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

    /// @dev Should upgrade to a new implementation
    function test_UpgradeTo() public virtual {
        address newImpl = address(new Distributor());
        vm.expectEmit(true, true, true, true);
        emit ERC1967Utils.Upgraded(newImpl);
        vm.prank(governance);
        distributor.upgradeToAndCall(newImpl, bytes(""));
        assertEq(vm.load(address(distributor), ERC1967Utils.IMPLEMENTATION_SLOT), bytes32(uint256(uint160(newImpl))));
    }

    /// @dev Should fail if initialize again
    function test_FailIfInitializeAgain() public virtual {
        vm.expectRevert();
        distributor.initialize(
            address(beraChef), address(bgt), address(blockRewardController), governance, beaconVerifier
        );
    }

    /// @dev Test when the reward rate is zero.
    function test_ZeroRewards() public {
        vm.startPrank(governance);
        blockRewardController.setRewardRate(0);
        blockRewardController.setMinBoostedRewardRate(0);
        vm.stopPrank();

        // expect a call to process the rewards
        bytes memory data = abi.encodeCall(IBlockRewardController.processRewards, (valPubkey, block.number));
        vm.expectCall(address(blockRewardController), data, 1);
        // expect no call to mint BGT
        data = abi.encodeCall(IBGT.mint, (address(distributor), 100 ether));
        vm.expectCall(address(bgt), data, 0);

        distributor.distributeFor(0, uint64(block.number), 0, valPubkey, dummyProof, dummyProof);
        assertEq(bgt.allowance(address(distributor), address(vault)), 0);
    }

    /// @dev Distribute using the default cutting board if none is set.
    function test_Distribute() public {
        vm.roll(distributor.getLastActionedBlock() + 1);

        // expect a call to process the rewards
        bytes memory data = abi.encodeCall(IBlockRewardController.processRewards, (valPubkey, block.number));
        vm.expectCall(address(blockRewardController), data, 1);
        // expect a call to mint the BGT to the distributor
        data = abi.encodeCall(IBGT.mint, (address(distributor), 100 ether));
        vm.expectCall(address(bgt), data, 1);
        // expect single call to check if ready then activate the queued cutting board
        // although it wont activate the queued cutting board since it nothing is queued.
        data = abi.encodeCall(IBeraChef.activateReadyQueuedCuttingBoard, (valPubkey, block.number));
        vm.expectCall(address(beraChef), data, 1);

        vm.expectEmit(true, true, true, true);
        emit IDistributor.Distributed(valPubkey, block.number, address(vault), 100 ether);
        distributor.distributeFor(0, uint64(block.number), 0, valPubkey, dummyProof, dummyProof);

        // check that the default cutting board was used
        // `getActiveCuttingBoard` should return default cutting board as there was no active cutting board queued by
        // the validator
        // the default cutting board was set with `1` as startBlock in RootHelperTest.
        assertEq(beraChef.getActiveCuttingBoard(valPubkey).startBlock, 1);
        assertEq(bgt.allowance(address(distributor), address(vault)), 100 ether);
    }

    /// @dev Test the `multicall` function for distributeFor.
    function test_DistributeMulticall() public {
        vm.roll(distributor.getLastActionedBlock() + 1);

        // expect 3 calls to process the rewards
        bytes memory data = abi.encodeCall(IBlockRewardController.processRewards, (valPubkey, block.number));
        vm.expectCall(address(blockRewardController), data, 1);
        data = abi.encodeCall(IBlockRewardController.processRewards, (valPubkey, block.number + 1));
        vm.expectCall(address(blockRewardController), data, 1);
        data = abi.encodeCall(IBlockRewardController.processRewards, (valPubkey, block.number + 2));
        vm.expectCall(address(blockRewardController), data, 1);
        // expect 3 calls to mint the BGT to the distributor
        data = abi.encodeCall(IBGT.mint, (address(distributor), 100 ether));
        vm.expectCall(address(bgt), data, 3);
        // expect 3 calls to check if ready then activate the queued cutting board
        // although it wont activate the queued cutting board since it nothing is queued.
        data = abi.encodeCall(IBeraChef.activateReadyQueuedCuttingBoard, (valPubkey, block.number));
        vm.expectCall(address(beraChef), data, 1);
        data = abi.encodeCall(IBeraChef.activateReadyQueuedCuttingBoard, (valPubkey, block.number + 1));
        vm.expectCall(address(beraChef), data, 1);
        data = abi.encodeCall(IBeraChef.activateReadyQueuedCuttingBoard, (valPubkey, block.number + 2));
        vm.expectCall(address(beraChef), data, 1);

        // call distributeFor 3 times in a single multicall
        bytes[] memory callData = new bytes[](3);
        callData[0] =
            abi.encodeCall(distributor.distributeFor, (0, uint64(block.number), 0, valPubkey, dummyProof, dummyProof));
        callData[1] = abi.encodeCall(
            distributor.distributeFor, (0, uint64(block.number + 1), 0, valPubkey, dummyProof, dummyProof)
        );
        callData[2] = abi.encodeCall(
            distributor.distributeFor, (0, uint64(block.number + 2), 0, valPubkey, dummyProof, dummyProof)
        );
        distributor.multicall(callData);

        // check that all 300 ether were distributed
        assertEq(beraChef.getActiveCuttingBoard(valPubkey).startBlock, 1);
        assertEq(bgt.allowance(address(distributor), address(vault)), 300 ether);
        assertEq(distributor.getLastActionedBlock(), block.number + 2);
        assertEq(distributor.getNextActionableBlock(), block.number + 3);
    }

    /// @dev Activate the queued cutting board if it is ready and distribute the rewards.
    function test_DistributeAndActivateQueuedCuttingBoard() public {
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](1);
        weights[0] = IBeraChef.Weight(address(vault), 10_000);
        uint64 startBlock = uint64(block.number + 2);

        vm.prank(operator);
        beraChef.queueNewCuttingBoard(valPubkey, startBlock, weights);

        // Distribute the rewards.
        vm.roll(startBlock);
        vm.prank(manager);
        distributor.resetCount(block.number);

        // expect a call to process the rewards
        bytes memory data = abi.encodeCall(IBlockRewardController.processRewards, (valPubkey, block.number));
        vm.expectCall(address(blockRewardController), data, 1);
        // expect a call to mint the BGT to the distributor
        data = abi.encodeCall(IBGT.mint, (address(distributor), 100 ether));
        vm.expectCall(address(bgt), data, 1);
        // expect a call to activate the queued cutting board
        data = abi.encodeCall(IBeraChef.activateReadyQueuedCuttingBoard, (valPubkey, block.number));
        vm.expectCall(address(beraChef), data, 1);

        vm.expectEmit(true, true, true, true);
        emit IDistributor.Distributed(valPubkey, block.number, address(vault), 100 ether);
        distributor.distributeFor(0, uint64(block.number), 0, valPubkey, dummyProof, dummyProof);

        // check that the queued cutting board was activated
        assertEq(beraChef.getActiveCuttingBoard(valPubkey).startBlock, startBlock);
        assertEq(bgt.allowance(address(distributor), address(vault)), 100 ether);
    }
}
