// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { LibClone } from "solady/src/utils/LibClone.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { Utils } from "../../libraries/Utils.sol";
import { IBerachainRewardsVaultFactory } from "../interfaces/IBerachainRewardsVaultFactory.sol";
import { BerachainRewardsVault } from "./BerachainRewardsVault.sol";

/// @title BerachainRewardsVaultFactory
/// @author Berachain Team
/// @notice Factory contract for creating BerachainRewardsVaults and keeping track of them.
contract BerachainRewardsVaultFactory is IBerachainRewardsVaultFactory, AccessControlUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The VAULT MANAGER role.
    bytes32 public constant VAULT_MANAGER_ROLE = keccak256("VAULT_MANAGER_ROLE");

    /// @notice The beacon address.
    address public beacon;

    /// @notice The BGT token address.
    address public bgt;

    /// @notice The distributor address.
    address public distributor;

    /// @notice The BeaconDeposit contract address.
    address public beaconDepositContract;

    /// @notice Mapping of staking token to vault address.
    mapping(address stakingToken => address vault) public getVault;

    /// @notice Array of all vaults that have been created.
    address[] public allVaults;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _bgt,
        address _distributor,
        address _beaconDepositContract,
        address _governance,
        address _vaultImpl
    )
        external
        initializer
    {
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        // slither-disable-next-line missing-zero-check
        bgt = _bgt;
        // slither-disable-next-line missing-zero-check
        distributor = _distributor;
        // slither-disable-next-line missing-zero-check
        beaconDepositContract = _beaconDepositContract;

        beacon = address(new UpgradeableBeacon(_governance, _vaultImpl));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          ADMIN                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        VAULT CREATION                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBerachainRewardsVaultFactory
    function createRewardsVault(address stakingToken) external returns (address) {
        if (getVault[stakingToken] != address(0)) VaultAlreadyExists.selector.revertWith();

        // Use solady library to deploy deterministic beacon proxy.
        bytes32 salt;
        assembly ("memory-safe") {
            mstore(0, stakingToken)
            salt := keccak256(0, 0x20)
        }
        address vault = LibClone.deployDeterministicERC1967BeaconProxy(beacon, salt);

        // Store the vault in the mapping and array.
        getVault[stakingToken] = vault;
        allVaults.push(vault);
        emit VaultCreated(stakingToken, vault);

        // Initialize the vault.
        BerachainRewardsVault(vault).initialize(beaconDepositContract, bgt, distributor, stakingToken);

        return vault;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          READS                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBerachainRewardsVaultFactory
    function predictRewardsVaultAddress(address stakingToken) external view returns (address) {
        bytes32 salt;
        assembly ("memory-safe") {
            mstore(0, stakingToken)
            salt := keccak256(0, 0x20)
        }
        return LibClone.predictDeterministicAddressERC1967BeaconProxy(beacon, salt, address(this));
    }

    /// @inheritdoc IBerachainRewardsVaultFactory
    function allVaultsLength() external view returns (uint256) {
        return allVaults.length;
    }
}
