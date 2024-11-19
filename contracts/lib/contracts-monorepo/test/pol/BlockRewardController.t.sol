// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import { IBGT } from "src/pol/interfaces/IBGT.sol";
import { IBlockRewardController, IPOLErrors } from "src/pol/interfaces/IBlockRewardController.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";

import { BeaconDepositMock, POLTest } from "./POL.t.sol";

contract BlockRewardControllerTest is POLTest {
    /// @dev Ensure that the contract is owned by the governance.
    function test_OwnerIsGovernance() public view {
        assertEq(blockRewardController.owner(), governance);
    }

    /// @dev Should fail if not the owner
    function test_FailIfNotOwner() public {
        vm.expectRevert();
        blockRewardController.transferOwnership(address(1));

        vm.expectRevert();
        blockRewardController.setDistributor(address(1));

        vm.expectRevert();
        blockRewardController.setRewardRate(255);

        address newImpl = address(new BlockRewardController());
        vm.expectRevert();
        blockRewardController.upgradeToAndCall(newImpl, bytes(""));
    }

    /// @dev Should upgrade to a new implementation
    function test_UpgradeTo() public {
        address newImpl = address(new BlockRewardController());
        vm.expectEmit(true, true, true, true);
        emit ERC1967Utils.Upgraded(newImpl);
        vm.prank(governance);
        blockRewardController.upgradeToAndCall(newImpl, bytes(""));
        assertEq(
            vm.load(address(blockRewardController), ERC1967Utils.IMPLEMENTATION_SLOT),
            bytes32(uint256(uint160(newImpl)))
        );
    }

    /// @dev Should fail if initialize again
    function test_FailIfInitializeAgain() public {
        vm.expectRevert();
        blockRewardController.initialize(address(bgt), address(distributor), address(beraChef), address(governance));
    }

    function test_SetDistributor_FailIfZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        blockRewardController.setDistributor(address(0));
    }

    /// @dev Ensure that the distributor is set
    function test_SetDistributor() public {
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        address _distributor = address(distributor);
        emit IBlockRewardController.SetDistributor(_distributor);
        blockRewardController.setDistributor(_distributor);
        assertEq(blockRewardController.distributor(), _distributor);
    }

    /// @dev Ensure that the base rate is set
    function test_SetBaseRate() public {
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BaseRateChanged(0, 1 ether);
        blockRewardController.setBaseRate(1 ether);
        assertEq(blockRewardController.baseRate(), 1 ether);
    }

    /// @dev Ensure that the reward rate is set
    function test_SetRewardRate() public {
        testFuzz_SetRewardRate(1 ether);
    }

    /// @dev Ensure that min boosted reward rate is also set
    function test_SetMinBoostedRewardRate() public {
        testFuzz_SetMinBoostedRewardRate(0.1 ether);
    }

    /// @dev Ensure that boost multiplier is also set
    function test_SetBoostMultiplier() public {
        testFuzz_SetBoostMultiplier(3 ether);
    }

    /// @dev Ensure that reward convexity is also set
    function test_SetRewardConvexity() public {
        testFuzz_SetRewardConvexity(0.5 ether);
    }

    /// @dev Parameterized setter for the reward rate
    function testFuzz_SetRewardRate(uint256 rewardRate) public {
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.RewardRateChanged(0, rewardRate);
        blockRewardController.setRewardRate(rewardRate);
        assertEq(blockRewardController.rewardRate(), rewardRate);
    }

    /// @dev Parameterized setter for min boosted reward rate
    function testFuzz_SetMinBoostedRewardRate(uint256 min) public {
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.MinBoostedRewardRateChanged(0, min);
        blockRewardController.setMinBoostedRewardRate(min);
        assertEq(blockRewardController.minBoostedRewardRate(), min);
    }

    /// @dev Parameterized setter for boost multiplier
    function testFuzz_SetBoostMultiplier(uint256 multiplier) public {
        multiplier = _bound(multiplier, 0, 1e6 ether);
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BoostMultiplierChanged(0, multiplier);
        blockRewardController.setBoostMultiplier(multiplier);
        assertEq(blockRewardController.boostMultiplier(), multiplier);
    }

    /// @dev Parameterized setter for reward convexity
    function testFuzz_SetRewardConvexity(int256 convexity) public {
        convexity = _bound(convexity, 0, 1 ether);
        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.RewardConvexityChanged(0, convexity);
        blockRewardController.setRewardConvexity(convexity);
        assertEq(blockRewardController.rewardConvexity(), convexity);
    }

    /// @dev Should fail if not the distributor
    function test_FailIfNotDistributor() public {
        vm.expectRevert();
        blockRewardController.processRewards(valPubkey, block.number);
    }

    /// @dev Should process zero rewards
    function test_ProcessZeroRewards() public {
        test_SetDistributor();

        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BlockRewardProcessed(block.number, 0, 0, 0);
        assertEq(blockRewardController.processRewards(valPubkey, block.number), 0);
    }

    /// @dev Should process rewards
    function test_ProcessRewards() public {
        test_SetDistributor();
        test_SetBaseRate();
        test_SetRewardRate();
        test_SetMinBoostedRewardRate();
        test_SetBoostMultiplier();
        test_SetRewardConvexity();

        // @dev should process min reward given no boosts
        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BlockRewardProcessed(block.number, 1 ether, 0, 0.1 ether);

        // expect calls to mint BGT to the distributor and coinbase
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (operator, 1.0 ether)));
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (address(distributor), 0.1 ether)));
        assertEq(blockRewardController.processRewards(valPubkey, block.number), 0.1 ether);
    }

    /// @dev Should mint commission to coinbase
    function test_ProcessRewardsWithCommission() public {
        test_SetDistributor();
        test_SetBaseRate();
        test_SetRewardRate();
        test_SetMinBoostedRewardRate();
        test_SetBoostMultiplier();
        test_SetRewardConvexity();

        vm.prank(operator);
        bgt.queueCommissionChange(valPubkey, 500); // 5%
        vm.roll(block.number + HISTORY_BUFFER_LENGTH + 1); // roll till the history buffer is full
        bgt.activateCommissionChange(valPubkey);

        uint256 balBeforeCoinbase = bgt.balanceOf(operator);
        uint256 balBeforeDistributor = bgt.balanceOf(address(distributor));

        // @dev should process min reward given no boosts
        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BlockRewardProcessed(block.number, 1 ether, 0.005 ether, 0.095 ether);

        // expect calls to mint BGT to the distributor and coinbase
        bytes memory distributorData = abi.encodeCall(IBGT.mint, (address(distributor), 0.095 ether));
        bytes memory commissionData = abi.encodeCall(IBGT.mint, (operator, 1.005 ether));
        vm.expectCall(address(bgt), distributorData, 1);
        vm.expectCall(address(bgt), commissionData, 1);
        assertEq(blockRewardController.processRewards(valPubkey, block.number), 0.095 ether);

        assertEq(bgt.balanceOf(operator), balBeforeCoinbase + 1.005 ether);
        assertEq(bgt.balanceOf(address(distributor)), balBeforeDistributor + 0.095 ether);
    }

    /// @dev Should process the maximum number of rewards without reverting (100% boost to the validator)
    function test_ProcessRewardsMax() public {
        _helper_ControllerSetters(1.5 ether, 0, 3 ether, 0.5 ether);
        _helper_Boost(address(0x1), 1 ether, valPubkey);

        // @dev should process max reward given 100% boosts to the user
        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BlockRewardProcessed(block.number, 1 ether, 0, 4.5 ether);

        // expect calls to mint BGT to the distributor and coinbase
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (operator, 1.0 ether)));
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (address(distributor), 4.5 ether)));
        assertEq(blockRewardController.processRewards(valPubkey, block.number), 4.5 ether);
    }

    /// @dev Should process the minimum number of rewards without reverting (0% boost to the validator)
    function test_ProcessRewardsMin() public {
        _helper_ControllerSetters(1.5 ether, 0.1 ether, 3 ether, 0.5 ether);

        // @dev should process min reward given no boosts
        vm.prank(address(distributor));
        vm.expectEmit(true, true, true, true);
        emit IBlockRewardController.BlockRewardProcessed(block.number, 1 ether, 0, 0.1 ether);

        // expect calls to mint BGT to the distributor and coinbase
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (operator, 1.0 ether)));
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (address(distributor), 0.1 ether)));
        assertEq(blockRewardController.processRewards(valPubkey, block.number), 0.1 ether);
    }

    /// @dev Should process rewards without reverting (boost distributed among 2 validators)
    function testFuzz_ProcessRewards(
        uint256 rewardRate,
        uint256 minReward,
        uint256 multiplier,
        int256 convexity,
        uint256 boostVal0,
        uint256 boostVal1
    )
        public
    {
        rewardRate = _bound(rewardRate, 0, 1e6 ether);
        minReward = _bound(minReward, 0, 1e3 ether);
        multiplier = _bound(multiplier, 0, 1e6 ether);
        convexity = _bound(convexity, 0, 1 ether);

        bytes memory valPubkey1 = "validator 1 pubkey";
        address operator1 = makeAddr("operator");
        BeaconDepositMock(beaconDepositContract).setOperator(valPubkey1, operator1);

        _helper_ControllerSetters(rewardRate, minReward, multiplier, convexity);
        _helper_Boost(address(0x2), boostVal0, valPubkey);
        _helper_Boost(address(0x3), boostVal1, valPubkey1);

        vm.prank(address(distributor));
        // expect calls to mint BGT to the distributor
        vm.expectCall(address(bgt), abi.encodeCall(IBGT.mint, (operator, 1.0 ether)));
        // expect reward between formula's min and max
        uint256 reward = blockRewardController.processRewards(valPubkey, block.number);
        assertGe(reward, minReward);
        uint256 maxReward = multiplier * rewardRate / 1e18;
        maxReward = maxReward > minReward ? maxReward : minReward;

        assertLe(reward, maxReward);
    }

    function _helper_ControllerSetters(
        uint256 rewardRate,
        uint256 minReward,
        uint256 multiplier,
        int256 convexity
    )
        internal
    {
        test_SetDistributor();
        test_SetBaseRate();
        testFuzz_SetRewardRate(rewardRate);
        testFuzz_SetMinBoostedRewardRate(minReward);
        testFuzz_SetBoostMultiplier(multiplier);
        testFuzz_SetRewardConvexity(convexity);

        vm.deal(address(bgt), address(bgt).balance + rewardRate * multiplier / 1e18); // add max bgt minted in a block
    }

    function _helper_Mint(address user, uint256 amount) internal {
        vm.deal(address(bgt), address(bgt).balance + amount);
        vm.prank(address(blockRewardController));
        bgt.mint(user, amount);
    }

    function _helper_QueueBoost(address user, bytes memory pubkey, uint256 amount) internal {
        _helper_Mint(user, amount);
        vm.prank(user);
        bgt.queueBoost(pubkey, uint128(amount));
    }

    function _helper_ActivateBoost(address caller, address user, bytes memory pubkey, uint256 amount) internal {
        _helper_QueueBoost(user, pubkey, amount);
        (uint32 blockNumberLast,) = bgt.boostedQueue(user, valPubkey);
        vm.roll(block.number + blockNumberLast + HISTORY_BUFFER_LENGTH + 1);
        vm.prank(caller);
        bgt.activateBoost(user, pubkey);
    }

    function _helper_Boost(address user, uint256 amount, bytes memory pubkey) internal {
        amount = _bound(amount, 1, type(uint128).max / 2);
        _helper_ActivateBoost(user, user, pubkey, amount);
    }
}
