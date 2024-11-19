// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IPOLErrors } from "../interfaces/IPOLErrors.sol";

interface IBerachainRewardsVaultFactory is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Emitted when a new vault is created.
     * @param stakingToken The address of the staking token.
     * @param vault The address of the vault.
     */
    event VaultCreated(address indexed stakingToken, address indexed vault);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         VAULT CREATION                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Creates a new rewards vault vault for the given staking token.
     * @param stakingToken The address of the staking token.
     * @return The address of the new vault.
     */
    function createRewardsVault(address stakingToken) external returns (address);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          READS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Gets the VAULT_MANAGER_ROLE.
     * @return The VAULT_MANAGER_ROLE.
     */
    function VAULT_MANAGER_ROLE() external view returns (bytes32);

    /**
     * @notice Gets the vault for the given staking token.
     * @param stakingToken The address of the staking token.
     * @return The address of the vault.
     */
    function getVault(address stakingToken) external view returns (address);

    /**
     * @notice Gets the number of vaults that have been created.
     * @return The number of vaults.
     */
    function allVaultsLength() external view returns (uint256);

    /**
     * @notice Predicts the address of the rewards vault for the given staking token.
     * @param stakingToken The address of the staking token.
     * @return The address of the rewards vault.
     */
    function predictRewardsVaultAddress(address stakingToken) external view returns (address);
}
