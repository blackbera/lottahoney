// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import { IPOLErrors } from "./IPOLErrors.sol";
import { IStakingRewards } from "../../base/IStakingRewards.sol";

interface IBerachainRewardsVault is IPOLErrors, IStakingRewards {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a delegate has staked on behalf of an account.
    /// @param account The account whose delegate has staked.
    /// @param delegate The delegate that has staked.
    /// @param amount The amount of staked tokens.
    event DelegateStaked(address indexed account, address indexed delegate, uint256 amount);

    /// @notice Emitted when a delegate has withdrawn on behalf of an account.
    /// @param account The account whose delegate has withdrawn.
    /// @param delegate The delegate that has withdrawn.
    /// @param amount The amount of withdrawn tokens.
    event DelegateWithdrawn(address indexed account, address indexed delegate, uint256 amount);

    /// @notice Emitted when a token has been recovered.
    /// @param token The token that has been recovered.
    /// @param amount The amount of token recovered.
    event Recovered(address token, uint256 amount);

    /// @notice Emitted when the msg.sender has set an operator to handle its rewards.
    /// @param account The account that has set the operator.
    /// @param operator The operator that has been set.
    event OperatorSet(address account, address operator);

    /// @notice Emitted when the distributor is set.
    /// @param distributor The address of the distributor.
    event DistributorSet(address indexed distributor);

    /// @notice Emitted when an incentive token is whitelisted.
    /// @param token The address of the token that has been whitelisted.
    /// @param minIncentiveRate The minimum amount of the token to incentivize per BGT emission.
    event IncentiveTokenWhitelisted(address indexed token, uint256 minIncentiveRate);

    /// @notice Emitted when an incentive token is removed.
    /// @param token The address of the token that has been removed.
    event IncentiveTokenRemoved(address indexed token);

    /// @notice Emitted when maxIncentiveTokensCount is updated.
    /// @param maxIncentiveTokensCount The max count of incentive tokens.
    event MaxIncentiveTokensCountUpdated(uint8 maxIncentiveTokensCount);

    /// @notice Emitted when incentives are processed for the operator of a validator.
    event IncentivesProcessed(bytes indexed pubkey, address indexed token, uint256 bgtEmitted, uint256 amount);

    /// @notice Emitted when incentives fail to be processed for the operator of a validator.
    event IncentivesProcessFailed(bytes indexed pubkey, address indexed token, uint256 bgtEmitted, uint256 amount);

    /// @notice Emitted when incentives are added to the vault.
    /// @param token The incentive token.
    /// @param sender The address that added the incentive.
    /// @param amount The amount of the incentive.
    /// @param incentiveRate The amount of the token to incentivize per BGT emission.
    event IncentiveAdded(address indexed token, address sender, uint256 amount, uint256 incentiveRate);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Get the address that is allowed to distribute rewards.
    /// @return The address that is allowed to distribute rewards.
    function distributor() external view returns (address);

    /// @notice Get the operator for an account.
    /// @param account The account to get the operator for.
    /// @return The operator for the account.
    function operator(address account) external view returns (address);

    /// @notice Get the count of active incentive tokens.
    /// @return The count of active incentive tokens.
    function getWhitelistedTokensCount() external view returns (uint256);

    /// @notice Get the list of whitelisted tokens.
    /// @return The list of whitelisted tokens.
    function getWhitelistedTokens() external view returns (address[] memory);

    /// @notice Get the total amount staked by delegates.
    /// @return The total amount staked by delegates.
    function getTotalDelegateStaked(address account) external view returns (uint256);

    /// @notice Get the amount staked by a delegate on behalf of an account.
    /// @return The amount staked by a delegate.
    function getDelegateStake(address account, address delegate) external view returns (uint256);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         ADMIN                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Initialize the vault, this is only callable once and by the factory since its the deployer.
     * @param _berachef The address of the berachef.
     * @param _bgt The address of the BGT token.
     * @param _distributor The address of the distributor.
     * @param _stakingToken The address of the staking token.
     */
    function initialize(address _berachef, address _bgt, address _distributor, address _stakingToken) external;

    /// @notice Allows the owner to set the contract that is allowed to distribute rewards.
    /// @param _rewardDistribution The address that is allowed to distribute rewards.
    function setDistributor(address _rewardDistribution) external;

    /// @notice Allows the distributor to notify the reward amount.
    /// @param pubkey The pubkey of the validator.
    /// @param reward The amount of reward to notify.
    function notifyRewardAmount(bytes calldata pubkey, uint256 reward) external;

    /// @notice Allows the owner to recover any ERC20 token from the vault.
    /// @param tokenAddress The address of the token to recover.
    /// @param tokenAmount The amount of token to recover.
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

    /// @notice Allows the owner to update the duration of the rewards.
    /// @param _rewardsDuration The new duration of the rewards.
    function setRewardsDuration(uint256 _rewardsDuration) external;

    /// @notice Allows the owner to whitelist a token to incentivize with.
    /// @param token The address of the token to whitelist.
    /// @param minIncentiveRate The minimum amount of the token to incentivize per BGT emission.
    function whitelistIncentiveToken(address token, uint256 minIncentiveRate) external;

    /// @notice Allows the owner to remove a whitelisted incentive token.
    /// @param token The address of the token to remove.
    function removeIncentiveToken(address token) external;

    /// @notice Allows the owner to update the maxIncentiveTokensCount.
    /// @param _maxIncentiveTokensCount The new maxIncentiveTokens count.
    function setMaxIncentiveTokensCount(uint8 _maxIncentiveTokensCount) external;

    /// @notice Allows the owner to pause the vault.
    function pause() external;

    /// @notice Allows the owner to unpause the vault.
    function unpause() external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MUTATIVE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Exit the vault with the staked tokens and claim the reward.
    /// @dev Only the account holder can call this function, not the operator.
    /// @dev Clears out the user self-staked balance and rewards.
    /// @param recipient The address to send the 'BGT' reward to.
    function exit(address recipient) external;

    /// @notice Claim the reward.
    /// @dev The operator only handles BGT, not STAKING_TOKEN.
    /// @dev Callable by the operator or the account holder.
    /// @param account The account to get the reward for.
    /// @param recipient The address to send the reward to.
    /// @return The amount of the reward claimed.
    function getReward(address account, address recipient) external returns (uint256);

    /// @notice Stake tokens in the vault.
    /// @param amount The amount of tokens to stake.
    function stake(uint256 amount) external;

    /// @notice Stake tokens on behalf of another account.
    /// @param account The account to stake for.
    /// @param amount The amount of tokens to stake.
    function delegateStake(address account, uint256 amount) external;

    /// @notice Withdraw the staked tokens from the vault.
    /// @param amount The amount of tokens to withdraw.
    function withdraw(uint256 amount) external;

    /// @notice Withdraw tokens staked on behalf of another account by the delegate (msg.sender).
    /// @param account The account to withdraw for.
    /// @param amount The amount of tokens to withdraw.
    function delegateWithdraw(address account, uint256 amount) external;

    /// @notice Allows msg.sender to set another address to claim and manage their rewards.
    /// @param _operator The address that will be allowed to claim and manage rewards.
    function setOperator(address _operator) external;

    /// @notice Add an incentive to the vault.
    /// @param token The address of the token to add as an incentive.
    /// @param amount The amount of the token to add as an incentive.
    /// @param incentiveRate The amount of the token to incentivize per BGT emission.
    function addIncentive(address token, uint256 amount, uint256 incentiveRate) external;
}
