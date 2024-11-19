// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { Multicallable } from "solady/src/utils/Multicallable.sol";

import { Utils } from "../../libraries/Utils.sol";
import { IBeraChef } from "../interfaces/IBeraChef.sol";
import { IBlockRewardController } from "../interfaces/IBlockRewardController.sol";
import { IDistributor } from "../interfaces/IDistributor.sol";
import { IBerachainRewardsVault } from "../interfaces/IBerachainRewardsVault.sol";
import { IBeaconVerifier } from "../interfaces/IBeaconVerifier.sol";
import { RootHelper } from "../RootHelper.sol";

/// @title Distributor
/// @author Berachain Team
/// @notice The Distributor contract is responsible for distributing the block rewards from the reward controller
/// and the cutting board weights, to the cutting board receivers.
/// @dev Each coinbase has its own cutting board, if it does not exist, a default cutting board is used.
/// And if governance has not set the default cutting board, the rewards are not minted and distributed.
contract Distributor is IDistributor, RootHelper, AccessControlUpgradeable, UUPSUpgradeable, Multicallable {
    using Utils for bytes4;
    using Utils for address;

    /// @notice The MANAGER role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @dev Represents 100%. Chosen to be less granular.
    uint96 internal constant ONE_HUNDRED_PERCENT = 1e4;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The BeraChef contract that we are getting the cutting board from.
    IBeraChef public beraChef;

    /// @notice The rewards controller contract that we are getting the rewards rate from.
    /// @dev And is responsible for minting the BGT token.
    IBlockRewardController public blockRewardController;

    /// @notice The BGT token contract that we are distributing to the cutting board receivers.
    address public bgt;

    // address of beacon verifier contract
    IBeaconVerifier public beaconVerifier;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _berachef,
        address _bgt,
        address _blockRewardController,
        address _governance,
        address _beaconVerifier
    )
        external
        initializer
    {
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        beraChef = IBeraChef(_berachef);
        bgt = _bgt;
        blockRewardController = IBlockRewardController(_blockRewardController);
        beaconVerifier = IBeaconVerifier(_beaconVerifier);
        emit BeaconVerifierSet(_beaconVerifier);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    function resetCount(uint256 _block) public override onlyRole(MANAGER_ROLE) {
        super.resetCount(_block);
    }

    function setBeaconVerifier(address _beaconVerifier) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_beaconVerifier == address(0)) {
            ZeroAddress.selector.revertWith();
        }
        beaconVerifier = IBeaconVerifier(_beaconVerifier);
        emit BeaconVerifierSet(_beaconVerifier);
    }

    /// @inheritdoc IDistributor
    function distributeFor(
        uint64 timestamp,
        uint64 blockNumber,
        uint64 proposerIndex,
        bytes calldata pubkey,
        bytes32[] calldata pubkeyProof,
        bytes32[] calldata blockNumberProof
    )
        external
    {
        uint256 nextActionableBlock = getNextActionableBlock();
        // Check if next block is actionable, revert if not.
        if (blockNumber != nextActionableBlock) {
            NotActionableBlock.selector.revertWith();
        }

        // Verify the pubkey and execution block number.
        beaconVerifier.verifyBeaconBlockProposer(timestamp, proposerIndex, pubkey, pubkeyProof);
        beaconVerifier.verifyExecutionNumber(timestamp, blockNumber, blockNumberProof);

        // Distribute the rewards.
        _distributeFor(pubkey, blockNumber);
        _incrementBlock(nextActionableBlock);
    }

    function _distributeFor(bytes calldata pubkey, uint256 blockNumber) internal {
        // Process the rewards with the block rewards controller for the specified block number.
        // Its dependent on the beraChef being ready, if not it will return zero rewards for the current block.
        uint256 rewardRate = blockRewardController.processRewards(pubkey, blockNumber);
        if (!beraChef.isReady() || rewardRate == 0) {
            // If berachef is not ready (genesis) or there aren't rewards to distribute, skip. This will skip since
            // there is no default cutting board.
            return;
        }

        // Activate the queued cutting board if it is ready.
        beraChef.activateReadyQueuedCuttingBoard(pubkey, blockNumber);

        // Get the active cutting board for the validator.
        // This will return the default cutting board if the validator does not have an active cutting board.
        IBeraChef.CuttingBoard memory cb = beraChef.getActiveCuttingBoard(pubkey);

        IBeraChef.Weight[] memory weights = cb.weights;
        uint256 length = weights.length;
        for (uint256 i; i < length;) {
            IBeraChef.Weight memory weight = weights[i];
            address receiver = weight.receiver;

            // Calculate the reward for the receiver: (rewards * weightPercentage / ONE_HUNDRED_PERCENT).
            uint256 rewardAmount =
                FixedPointMathLib.fullMulDiv(rewardRate, weight.percentageNumerator, ONE_HUNDRED_PERCENT);

            // The reward vault will pull the rewards from this contract so we can keep the approvals for the
            // soul bound token BGT clean.
            bgt.safeIncreaseAllowance(receiver, rewardAmount);

            // Notify the receiver of the reward.
            IBerachainRewardsVault(receiver).notifyRewardAmount(pubkey, rewardAmount);

            emit Distributed(pubkey, blockNumber, receiver, rewardAmount);

            unchecked {
                ++i;
            }
        }
    }
}
