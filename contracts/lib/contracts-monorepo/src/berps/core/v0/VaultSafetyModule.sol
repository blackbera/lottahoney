// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IFeeCollector } from "../../../pol/interfaces/IFeeCollector.sol";
import { IVault } from "../../interfaces/v0/IVault.sol";
import { IVaultSafetyModule } from "../../interfaces/v0/IVaultSafetyModule.sol";
import { BerpsErrors } from "../../utils/BerpsErrors.sol";
import { Utils } from "../../../libraries/Utils.sol";

contract VaultSafetyModule is UUPSUpgradeable, IVaultSafetyModule {
    using Utils for bytes4;
    using Utils for address;
    using SafeTransferLib for address;

    /// @inheritdoc IVaultSafetyModule
    address public manager;
    address public asset;
    IVault public vault;
    IFeeCollector public feeCollector;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyManager { }

    /// @inheritdoc IVaultSafetyModule
    function initialize(
        address _manager,
        address _asset,
        address _vault,
        address _feeCollector
    )
        external
        initializer
    {
        if (
            _manager == address(0) || _asset == address(0) || _vault == address(0)
                || address(_feeCollector) == address(0)
        ) BerpsErrors.WrongParams.selector.revertWith();

        manager = _manager;
        asset = _asset;
        vault = IVault(_vault);
        feeCollector = IFeeCollector(_feeCollector);
    }

    modifier onlyManager() {
        if (msg.sender != manager) BerpsErrors.Unauthorized.selector.revertWith();
        _;
    }

    /// @inheritdoc IVaultSafetyModule
    function updateManager(address newManager) external onlyManager {
        if (newManager == address(0)) BerpsErrors.WrongParams.selector.revertWith();
        manager = newManager;
        emit AddressUpdated("manager", newManager);
    }

    /// @inheritdoc IVaultSafetyModule
    function updateVault(address newVault) external onlyManager {
        if (newVault == address(0)) BerpsErrors.WrongParams.selector.revertWith();
        vault = IVault(newVault);
        emit AddressUpdated("vault", newVault);
    }

    /// @inheritdoc IVaultSafetyModule
    function updateAsset(address newAsset) external onlyManager {
        if (newAsset == address(0)) BerpsErrors.WrongParams.selector.revertWith();
        asset = newAsset;
        emit AddressUpdated("asset", newAsset);
    }

    /// @inheritdoc IVaultSafetyModule
    function updateFeeCollector(address newFeeCollector) external onlyManager {
        if (newFeeCollector == address(0)) BerpsErrors.WrongParams.selector.revertWith();
        feeCollector = IFeeCollector(newFeeCollector);
        emit AddressUpdated("feeCollector", newFeeCollector);
    }

    /// @inheritdoc IVaultSafetyModule
    function recapitalize(uint256 amount) public onlyManager {
        if (amount == 0) BerpsErrors.WrongParams.selector.revertWith();

        asset.safeApprove(address(vault), amount);
        vault.recapitalize(amount);

        emit Recapitalized(amount, vault.collateralizationP());
    }

    /// @inheritdoc IVaultSafetyModule
    function recapitalizeAll() external onlyManager {
        recapitalize(asset.balanceOf(address(this)));
    }

    /// @inheritdoc IVaultSafetyModule
    function donateToPoL(uint256 amount) public onlyManager {
        if (amount == 0) BerpsErrors.WrongParams.selector.revertWith();

        if (feeCollector.payoutToken() == address(asset)) {
            asset.safeApprove(address(feeCollector), amount);
            feeCollector.donate(amount);
        } else {
            asset.safeTransfer(address(feeCollector), amount);
        }

        emit DonatedToPoL(amount, vault.totalDeposited());
    }

    /// @inheritdoc IVaultSafetyModule
    function donateAllToPoL() external onlyManager {
        donateToPoL(asset.balanceOf(address(this)));
    }
}
