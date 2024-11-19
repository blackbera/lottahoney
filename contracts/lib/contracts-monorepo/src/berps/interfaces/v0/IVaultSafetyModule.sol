// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IVaultSafetyModule {
    /// @notice Emitted when any address is updated.
    event AddressUpdated(string name, address newValue);

    /// @notice Emitted when the safety module recapitalizes the vault.
    event Recapitalized(uint256 assets, uint256 collatPSnapshot);

    /// @notice Emitted when the safety module donates assets to BGT Stakers.
    event DonatedToPoL(uint256 assets, uint256 totalDepositedSnapshot);

    /// @notice Only callable via a ERC1967 Proxy contract.
    function initialize(address _manager, address _asset, address _vault, address _feeCollector) external;

    /// @notice The manager of the safety module.
    function manager() external view returns (address);

    /// @notice Updates the manager of the safety module.
    /// @notice Only callable by the manager.
    function updateManager(address newManager) external;

    /// @notice Updates the vault used by the safety module.
    /// @notice Only callable by the manager.
    function updateVault(address newVault) external;

    /// @notice Updates the asset used by the safety module.
    /// @notice Only callable by the manager.
    function updateAsset(address newAsset) external;

    /// @notice Updates the PoL FeeCollector used by the safety module.
    /// @notice Only callable by the manager.
    function updateFeeCollector(address newFeeCollector) external;

    /// @notice Recapitalizes the specified amount of assets from the safety module to the vault.
    /// @dev Will revert if the safety module does not have enough assets.
    /// @dev Will revert if the vault is sufficiently over-collateralized.
    /// @param amount The amount of assets to recapitalize (PRECISION 1e18)
    /// @notice Only callable by the manager.
    function recapitalize(uint256 amount) external;

    /// @notice Recapitalizes all the assets owned by the safety module to the vault.
    /// @dev Will revert if the safety module does not have any assets.
    /// @dev Will revert if the vault is sufficiently over-collateralized.
    /// @notice Only callable by the manager.
    function recapitalizeAll() external;

    /// @notice Donates the specified amount of assets from the safety module to BGT Stakers.
    /// @dev Will revert if the safety module does not have enough assets.
    /// @dev Will revert if the donate amount is less than the FeeCollector's payoutAmount.
    /// @param amount The amount of assets to recapitalize (PRECISION 1e18)
    /// @notice Only callable by the manager.
    function donateToPoL(uint256 amount) external;

    /// @notice Donates all the assets owned by the safety module to BGT Stakers.
    /// @dev Will revert if the safety module does not have any assets.
    /// @dev Will revert if the donate amount is less than the FeeCollector's payoutAmount.
    /// @notice Only callable by the manager.
    function donateAllToPoL() external;
}
