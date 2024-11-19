// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @notice Implementations is used for storing the addresses of the Berps V0 contracts implementations.
struct Implementations {
    address feesAccrued;
    address vault;
    address feesMarkets;
    address markets;
    address referrals;
    address entrypoint;
    address settlement;
    address orders;
    address vaultSafetyModule;
}

/// @notice Salts is used for deploying the Berps V0 contracts proxies with CREATE2.
struct Salts {
    uint256 feesAccrued;
    uint256 vault;
    uint256 feesMarkets;
    uint256 markets;
    uint256 referrals;
    uint256 entrypoint;
    uint256 settlement;
    uint256 orders;
    uint256 vaultSafetyModule;
}
