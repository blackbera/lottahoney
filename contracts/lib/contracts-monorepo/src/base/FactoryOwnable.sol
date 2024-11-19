// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IBerachainRewardsVaultFactory } from "../pol/interfaces/IBerachainRewardsVaultFactory.sol";

import { Utils } from "../libraries/Utils.sol";

/// @title FactoryOwnable
/// @author Berachain Team
/// @notice Contract module which provides a modifier for restricting access to the factory owner.
abstract contract FactoryOwnable is Initializable {
    using Utils for bytes4;

    /// @notice Throws if sender is not the owner of factory contract.
    /// @param account The address of the sender.
    error OwnableUnauthorizedAccount(address account);

    /// @custom:storage-location erc7201:berachain.storage.factoryOwnable
    struct FactoryOwnableStorage {
        address _factory;
    }

    // keccak256(abi.encode(uint256(keccak256("berachain.storage.factoryOwnable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FactoryOwnableStorageLocation =
        0x4e32a932fdd4658a66f9586d8955a0d0a795a01bd8251335b4fae29d972acc00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         INITIALIZER                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Must be called by the initializer of the inheriting contract.
    /// @param factoryAddr The address of the ownable factory contract.
    function __FactoryOwnable_init(address factoryAddr) internal onlyInitializing {
        _setFactory(factoryAddr);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Throws if called by any account other than the factory owner.
    modifier onlyFactoryOwner() {
        _checkFactoryOwner();
        _;
    }

    modifier onlyFactoryVaultManager() {
        _checkFactoryVaultManager();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         GETTERS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the address of the factory contract.
    function factory() public view virtual returns (address) {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        return $._factory;
    }

    /// @notice Returns if the user is a owner of the factory contract.
    function isFactoryOwner(address user) public view virtual returns (bool) {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        return AccessControlUpgradeable($._factory).hasRole(_getAdminRole(), user);
    }

    /// @notice Returns if the account is a vault manager of the factory contract.
    function isFactoryVaultManager(address user) public view virtual returns (bool) {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        return AccessControlUpgradeable($._factory).hasRole(_getVaultManagerRole(), user);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         INTERNALS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getAdminRole() internal view returns (bytes32) {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        return AccessControlUpgradeable($._factory).DEFAULT_ADMIN_ROLE();
    }

    function _getVaultManagerRole() internal view returns (bytes32) {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        return IBerachainRewardsVaultFactory($._factory).VAULT_MANAGER_ROLE();
    }

    /// @dev Returns the storage struct of the factory ownable contract.
    function _getFactoryOwnableStorage() internal pure returns (FactoryOwnableStorage storage $) {
        assembly {
            $.slot := FactoryOwnableStorageLocation
        }
    }

    /// @dev Sets the address of the factory contract.
    function _setFactory(address factoryAddr) internal {
        FactoryOwnableStorage storage $ = _getFactoryOwnableStorage();
        $._factory = factoryAddr;
    }

    /// @dev Checks if the sender is a admin of the factory contract.
    function _checkFactoryOwner() internal view {
        if (!isFactoryOwner(msg.sender)) OwnableUnauthorizedAccount.selector.revertWith(msg.sender);
    }

    /// @dev Check if the sender is a vault manager of the factory contract.
    function _checkFactoryVaultManager() internal view {
        if (!isFactoryVaultManager(msg.sender)) OwnableUnauthorizedAccount.selector.revertWith(msg.sender);
    }
}
