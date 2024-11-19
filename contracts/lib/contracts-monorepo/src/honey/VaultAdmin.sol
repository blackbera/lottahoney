// SPDX-License-Identifier: MIT
// To support named parameters in mapping types and custom operators for user-defined value types.
pragma solidity ^0.8.19;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { ERC4626 } from "solady/src/tokens/ERC4626.sol";
import { LibClone } from "solady/src/utils/LibClone.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { Utils } from "../libraries/Utils.sol";
import { IHoneyErrors } from "./IHoneyErrors.sol";
import { CollateralVault } from "./CollateralVault.sol";

/// @notice This is the admin contract that manages the vaults and fees.
/// @author Berachain Team
abstract contract VaultAdmin is AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable, IHoneyErrors {
    using Utils for bytes4;

    /// @notice Emitted when the fee receiver address is set.
    event FeeReceiverSet(address indexed feeReceiver);

    /// @notice Emitted when the POL Fee Collector address is set.
    event POLFeeCollectorSet(address indexed polFeeCollector);

    /// @notice Emitted when a new vault is created.
    event VaultCreated(address indexed vault, address indexed asset);

    /// @notice Emitted when collateral asset status is set.
    event CollateralAssetStatusSet(address indexed asset, bool isBadCollateral);

    /// @notice Emitted when a collected fee is withdrawn.
    event CollectedFeeWithdrawn(address indexed asset, address indexed receiver, uint256 shares, uint256 assets);

    /// @notice The MANAGER role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The beacon address.
    address public beacon;

    /// @notice The address of the fee receiver.
    address public feeReceiver;

    /// @notice The address of the POL Fee Collector.
    address public polFeeCollector;

    /// @notice Array of registered assets.
    address[] public registeredAssets;

    /// @notice Mapping of assets to their corresponding vaults.
    mapping(address asset => ERC4626 vault) public vaults;

    /// @notice Mapping of bad collateral assets.
    mapping(address asset => bool badCollateral) public isBadCollateralAsset;

    /// @notice Mapping of receiver to asset to collected fee.
    /// @dev Stores the shares of fees corresponding to the receiver that are not yet redeemed.
    mapping(address receiver => mapping(address asset => uint256 collectedFee)) public collectedFees;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         INITIALIZER                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Must be called by the initializer of the inheriting contract.
    /// @param _governance The address of the governance.
    /// @param _feeReceiver The address of the fee receiver.
    /// @param _polFeeCollector The address of the POL Fee Collector.
    function __VaultAdmin_init(
        address _governance,
        address _feeReceiver,
        address _polFeeCollector
    )
        internal
        onlyInitializing
    {
        beacon = address(new UpgradeableBeacon(_governance, address(new CollateralVault())));
        feeReceiver = _feeReceiver;
        polFeeCollector = _polFeeCollector;
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
        emit FeeReceiverSet(_feeReceiver);
        emit POLFeeCollectorSet(_polFeeCollector);
    }

    /// @notice Check if the asset is registered.
    modifier onlyRegisteredAsset(address asset) {
        if (address(vaults[asset]) == address(0)) {
            AssetNotRegistered.selector.revertWith(address(asset));
        }
        _;
    }

    /// @notice Check if the asset is not a bad collateral.
    modifier onlyGoodCollateralAsset(address asset) {
        if (isBadCollateralAsset[asset]) {
            AssetIsBadCollateral.selector.revertWith(asset);
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @notice Pause the contract.
    function pause() external onlyRole(MANAGER_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract.
    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }

    function pauseVault(address asset) external onlyRole(MANAGER_ROLE) onlyRegisteredAsset(asset) {
        CollateralVault(address(vaults[asset])).pause();
    }

    function unpauseVault(address asset) external onlyRole(MANAGER_ROLE) onlyRegisteredAsset(asset) {
        CollateralVault(address(vaults[asset])).unpause();
    }

    /// @dev Create a new ERC4626 vault for a pair of asset - Honey and register it with VaultAdmin.
    /// @param asset The asset to create a vault for.
    /// @return The newly created vault.
    function createVault(address asset) external onlyRole(DEFAULT_ADMIN_ROLE) returns (ERC4626) {
        if (address(vaults[asset]) != address(0)) {
            VaultAlreadyRegistered.selector.revertWith(address(asset));
        }
        registeredAssets.push(asset);

        // Use solady library to deploy deterministic beacon proxy.
        bytes32 salt;
        assembly ("memory-safe") {
            mstore(0, asset)
            salt := keccak256(0, 0x20)
        }
        CollateralVault vault = CollateralVault(LibClone.deployDeterministicERC1967BeaconProxy(beacon, salt));
        vault.initialize(asset);
        vaults[asset] = vault;

        emit VaultCreated(address(vault), address(asset));
        return vault;
    }

    /// @notice Set the fee receiver address.
    function setFeeReceiver(address _feeReceiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_feeReceiver == address(0)) ZeroAddress.selector.revertWith();
        feeReceiver = _feeReceiver;
        emit FeeReceiverSet(_feeReceiver);
    }

    /// @notice Set the POL Fee Collector address.
    function setPOLFeeCollector(address _polFeeCollector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_polFeeCollector == address(0)) ZeroAddress.selector.revertWith();
        polFeeCollector = _polFeeCollector;
        emit POLFeeCollectorSet(_polFeeCollector);
    }

    /// @notice Set the bad collateral status of an asset.
    /// @dev Only the owner can set the bad collateral status of an asset.
    /// @dev Only registered assets can be set as bad collateral.
    /// @dev If set to true, minting will be disabled for the asset.
    /// @param asset The address of the asset.
    /// @param _isBadCollateral The status of the asset.
    function setCollateralAssetStatus(
        address asset,
        bool _isBadCollateral
    )
        external
        onlyRole(MANAGER_ROLE)
        onlyRegisteredAsset(asset)
    {
        if (isBadCollateralAsset[asset] == _isBadCollateral) {
            AssestAlreadyInSameState.selector.revertWith(asset);
        }
        isBadCollateralAsset[asset] = _isBadCollateral;
        emit CollateralAssetStatusSet(asset, _isBadCollateral);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        FEE RELATED                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Withdraw all the collected fees for a `receiver`.
    function withdrawAllFees(address receiver) external {
        uint256 numAssets = numRegisteredAssets();
        for (uint256 i; i < numAssets;) {
            address asset = registeredAssets[i];
            _withdrawCollectedFee(asset, receiver, collectedFees[receiver][asset]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Withdraw the collected fees for a `receiver` for a specific `asset`.
    function withdrawFee(
        address asset,
        address receiver
    )
        external
        onlyRegisteredAsset(asset)
        returns (uint256 assets)
    {
        assets = _withdrawCollectedFee(asset, receiver, collectedFees[receiver][asset]);
    }

    function _withdrawCollectedFee(
        address asset,
        address receiver,
        uint256 shares
    )
        internal
        returns (uint256 assets)
    {
        if (shares == 0) return 0;
        collectedFees[receiver][asset] = 0;
        assets = vaults[asset].redeem(shares, receiver, address(this));
        emit CollectedFeeWithdrawn(asset, receiver, shares, assets);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Get the length of `registeredAssets` array.
    function numRegisteredAssets() public view returns (uint256) {
        return registeredAssets.length;
    }

    /// @notice Predicts the address of the vault for the given asset.
    /// @param asset The address of the asset.
    /// @return The address of the vault.
    function predictVaultAddress(address asset) external view returns (address) {
        bytes32 salt;
        assembly ("memory-safe") {
            mstore(0, asset)
            salt := keccak256(0, 0x20)
        }
        return LibClone.predictDeterministicAddressERC1967BeaconProxy(beacon, salt, address(this));
    }
}
