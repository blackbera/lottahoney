// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import { IPOLErrors } from "./IPOLErrors.sol";

interface IBlockRewardController is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Emitted when the constant base rate has changed.
     * @param oldBaseRate The old base rate.
     * @param newBaseRate The new base rate.
     */
    event BaseRateChanged(uint256 oldBaseRate, uint256 newBaseRate);

    /**
     * @notice Emitted when the reward rate has changed.
     * @param oldRewardRate The old reward rate.
     * @param newRewardRate The new reward rate.
     */
    event RewardRateChanged(uint256 oldRewardRate, uint256 newRewardRate);

    /**
     * @notice Emitted when the min boosted reward rate has changed.
     * @param oldMinBoostedRewardRate The old min boosted reward rate.
     * @param newMinBoostedRewardRate The new min boosted reward rate.
     */
    event MinBoostedRewardRateChanged(uint256 oldMinBoostedRewardRate, uint256 newMinBoostedRewardRate);

    /**
     * @notice Emitted when the boostMultiplier parameter has changed.
     * @param oldBoostMultiplier The old boost multiplier parameter.
     * @param newBoostMultiplier The new boost multiplier parameter.
     */
    event BoostMultiplierChanged(uint256 oldBoostMultiplier, uint256 newBoostMultiplier);

    /**
     * @notice Emitted when the reward formula convexity parameter has changed.
     * @param oldRewardConvexity The old reward formula convexity parameter.
     * @param newRewardConvexity The new reward formula convexity parameter.
     */
    event RewardConvexityChanged(int256 oldRewardConvexity, int256 newRewardConvexity);

    /// @notice Emitted when the distributor is set.
    event SetDistributor(address indexed rewardDistribution);

    /// @notice Emitted when the rewards for the specified block have been processed.
    /// @param blockNumber The block number that was processed.
    /// @param baseRate The base amount of BGT minted to the validator's operator.
    /// @param commissionRate The commission amount of BGT minted to the validator's operator.
    /// @param rewardRate The amount of BGT minted to the distributor.
    event BlockRewardProcessed(uint256 blockNumber, uint256 baseRate, uint256 commissionRate, uint256 rewardRate);

    /// @notice Returns the constant base rate for BGT.
    /// @return The constant base amount of BGT to be minted in the current block.
    function baseRate() external view returns (uint256);

    /// @notice Returns the reward rate for BGT.
    /// @return The unscaled amount of BGT to be minted in the current block.
    function rewardRate() external view returns (uint256);

    /// @notice Returns the minimum boosted reward rate for BGT.
    /// @return The minimum amount of BGT to be minted in the current block.
    function minBoostedRewardRate() external view returns (uint256);

    /// @notice Returns the boost mutliplier param in the reward function.
    /// @return The parameter that determines the inflation cap.
    function boostMultiplier() external view returns (uint256);

    /// @notice Returns the reward convexity param in the reward function.
    /// @return The parameter that determines how fast the function converges to its max.
    function rewardConvexity() external view returns (int256);

    /**
     * @notice processes the rewards for the specified block and mints the BGT to the distributor and commissions to
     * validator's operator.
     * @dev This function can only be called by the distributor.
     * @param pubkey The validator's pubkey.
     * @param blockNumber The block number to process rewards for.
     * @return the amount of BGT minted to distributor.
     */
    function processRewards(bytes calldata pubkey, uint256 blockNumber) external returns (uint256);

    /**
     * @notice Sets the constant base reward rate for BGT.
     * @dev This function can only be called by the owner, which is the governance address.
     * @param _baseRate The new base rate.
     */
    function setBaseRate(uint256 _baseRate) external;

    /**
     * @notice Sets the reward rate for BGT.
     * @dev This function can only be called by the owner, which is the governance address.
     * @param _rewardRate The new reward rate.
     */
    function setRewardRate(uint256 _rewardRate) external;

    /**
     * @notice Sets the min boosted reward rate for BGT.
     * @dev This function can only be called by the owner, which is the governance address.
     * @param _minBoostedRewardRate The new min boosted reward rate.
     */
    function setMinBoostedRewardRate(uint256 _minBoostedRewardRate) external;

    /**
     * @notice Sets the boost multiplier parameter for the reward formula.
     * @dev This function can only be called by the owner, which is the governance address.
     * @param _boostMultiplier The new boost multiplier.
     */
    function setBoostMultiplier(uint256 _boostMultiplier) external;

    /**
     * @notice Sets the reward convexity parameter for the reward formula.
     * @dev This function can only be called by the owner, which is the governance address.
     * @param _rewardConvexity The new reward convexity.
     */
    function setRewardConvexity(int256 _rewardConvexity) external;

    /**
     * @notice Sets the distributor contract that receives the minted BGT.
     * @dev This function can only be called by the owner, which is the governance address.
     * @param _distributor The new distributor contract.
     */
    function setDistributor(address _distributor) external;
}
