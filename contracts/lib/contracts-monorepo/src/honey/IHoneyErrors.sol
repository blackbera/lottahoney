// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice Interface of Honey errors
interface IHoneyErrors {
    // Signature: 0xd92e233d
    error ZeroAddress();
    // Signature: 0x14799671
    error MismatchedOwner(address owner, address expectedOwner);
    // Signature: 0x38bfcc16
    error VaultAlreadyRegistered(address asset);
    // Signature: 0x1a2a9e87
    error AssetNotRegistered(address asset);
    // Signature: 0x536dd9ef
    error UnauthorizedCaller(address caller, address expectedCaller);
    // Signature: 0xada46d16
    error OverOneHundredPercentRate(uint256 rate);
    // Signature: 0x71fba9d0
    error UnderNinetyEightPercentRate(uint256 rate);
    // Signature: 0x32cc7236
    error NotFactory();
    // Signature: 0xb97fded1
    error InsufficientAssets(uint256 assets, uint256 shares);
    // Signature: 0x6ba2e418
    error AssetIsBadCollateral(address asset);
    // Signature: 0x665d568d
    error AssestAlreadyInSameState(address asset);
}
