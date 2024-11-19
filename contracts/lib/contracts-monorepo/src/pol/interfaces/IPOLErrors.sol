// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import { IStakingRewardsErrors } from "../../base/IStakingRewardsErrors.sol";

/// @notice Interface of POL errors
interface IPOLErrors is IStakingRewardsErrors {
    // Signature: 0xf2d81d95
    error NotApprovedSender();
    // Signature: 0x02e6c295
    error NotRootFollower();
    // Signature: 0x1db3b859
    error NotDelegate();
    // Signature: 0x53f0a596
    error NotBGT();
    // Signature: 0x1b0eb4ec
    error NotBlockRewardController();
    // Signature: 0x385296d5
    error NotDistributor();
    // Signature: 0x73fcd3fe
    error NotFeeCollector();
    // Signature: 0x495a2f88
    error NotFriendOfTheChef();
    // Signature: 0xb56f932c
    error NotGovernance();
    // Signature:0x7c214f04
    error NotOperator();
    // Signature: 0xad3a8b9e
    error NotEnoughBalance();
    // Signature: 0xadd377f6
    error InvalidActivateBoostDelay();
    // Signature: 0x2f14f4f9
    error InvalidDropBoostDelay();
    // Signature: 0x14969061
    error NotEnoughBoostedBalance();
    // Signature: 0xe8966d7a
    error NotEnoughTime();
    // Signature: 0xec2caa0d
    error InvalidStartBlock();
    // Signature: 0x5db25e4f
    error InvalidCuttingBoardWeights();
    // Signature: 0xdc81db85
    error InvalidCommission();
    // Signature: 0x347f95b2
    error InvalidRewardConvexity();
    // Signature: 0xb7b2319a
    error InvalidBoostMultiplier();
    // Signature: 0xca06e349
    error CommissionNotQueued();
    // Signature: 0xf6fae721
    error TooManyWeights();
    // Signature: 0x0dc149f0
    error AlreadyInitialized();
    // Signature: 0x04aabf33
    error VaultAlreadyExists();
    // Signature: 0xd92e233d
    error ZeroAddress();
    // Signature: 0x4ce307ee
    error CuttingBoardBlockDelayTooLarge();
    // Signature: 0x08519afa
    error NotFactoryVault();

    /*                           STAKING                           */

    // Signature: 0xe4ea100b
    error CannotRecoverRewardToken();
    // Signature: 0x1b813803
    error CannotRecoverStakingToken();
    // Signature: 0x2899103f
    error CannotRecoverIncentiveToken();
    // Signature: 0x97bad1bf
    error RewardCycleStarted();
    // Signature: 0x38432c89
    error IncentiveRateTooHigh();

    // Signature: 0xf84835a0
    error TokenNotWhitelisted();
    // Signature: 0x8d1473a6
    error InsufficientDelegateStake();
    // Signature: 0x08e88f46
    error InsufficientSelfStake();
    // Signature: 0xfbf97e07
    error TokenAlreadyWhitelistedOrLimitReached();
    // Signature: 0xad57d95d
    error AmountLessThanMinIncentiveRate();
    // Signature: 0xfbf1123c
    error InvalidMaxIncentiveTokensCount();

    // Signature: 0x546c7600
    error PayoutAmountIsZero();
    // Signature: 0x89c622a2
    error DonateAmountLessThanPayoutAmount();
    // Signature: 0xacac1f5f
    error MaxNumWeightsPerCuttingBoardIsZero();
    // Signature: 0x0b5c3aff
    error MinIncentiveRateIsZero();

    /// @dev Unauthorized caller
    // Signature: 0x8e4a23d6
    error Unauthorized(address);

    /// @dev The queried block is not in the buffer range
    // Signature: 0x68c0ab1c
    error BlockNotInBuffer();

    /// @dev distributeFor was called with a block number that is not the next actionable block
    // Signature: 0xb14ceca6
    error NotActionableBlock();

    /// @dev The block number does not exist yet
    // Signature: 0xfa4a5e45
    error BlockDoesNotExist();

    // Signature: 0x8e7572da
    error InvariantCheckFailed();
}
