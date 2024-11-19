// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IReferrals {
    struct ReferrerDetails {
        address[] tradersReferred;
        uint256 volumeReferredHoney; // 1e18
        uint256 pendingRewardsToken; // 1e18
        uint256 totalRewardsToken; // 1e18
        uint256 totalRewardsValueHoney; // 1e18
    }

    // EVENTS
    event UpdatedStartReferrerFeeP(uint256 value);
    event UpdatedOpenFeeP(uint256 value);
    event UpdatedTargetVolumeHoney(uint256 value);
    event ReferrerRegistered(address indexed trader, address indexed referrer);
    event ReferrerRewardDistributed(
        address indexed referrer, address indexed trader, uint256 volumeHoney, uint256 referredAmtHoney
    );

    /// @notice Only callable via a ERC1967 Proxy contract.
    function initialize(
        address _orders,
        uint256 _startReferrerFeeP,
        uint256 _openFeeP,
        uint256 _targetVolumeHoney
    )
        external;

    function registerPotentialReferrer(address referrer) external;

    function targetVolumeHoney() external view returns (uint256);

    function referrersCount() external view returns (uint256);

    function getReferrerDetails(address referrer) external view returns (ReferrerDetails memory);

    function getAllReferrerDetails(uint256 offset, uint256 count) external view returns (ReferrerDetails[] memory);

    function distributePotentialReward(
        address trader,
        uint256 volumeHoney,
        uint256 pairOpenFeeP
    )
        external
        returns (uint256);

    function getPercentOfOpenFeeP(address trader) external view returns (uint256);

    function getTraderReferrer(address trader) external view returns (address referrer);
}

/// @notice the only functions needed from the orders contract by Referrals.
interface IOrdersForReferrals {
    function settlement() external view returns (address);
    function gov() external view returns (address);
    function transferHoney(address, address, uint256) external;
}
