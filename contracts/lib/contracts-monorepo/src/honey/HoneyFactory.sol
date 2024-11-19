// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { ERC4626 } from "solady/src/tokens/ERC4626.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { Utils } from "../libraries/Utils.sol";
import { IHoneyFactory } from "./IHoneyFactory.sol";
import { Honey } from "./Honey.sol";
import { VaultAdmin } from "./VaultAdmin.sol";

/// @notice This is the factory contract for minting and redeeming Honey.
/// @author Berachain Team
contract HoneyFactory is IHoneyFactory, VaultAdmin {
    using Utils for bytes4;

    /// @dev The constant representing 100% of mint/redeem rate.
    uint256 private constant ONE_HUNDRED_PERCENT_RATE = 1e18;

    /// @dev The constant representing 98% of mint/redeem rate.
    uint256 private constant NINETY_EIGHT_PERCENT_RATE = 98e16;

    /// @notice The Honey token contract.
    Honey public honey;

    /// @notice The rate of POLFeeCollector fees, 60.18-decimal fixed-point number representation
    /// @dev 1e18 will imply all the fees are collected by the POLFeeCollector
    /// @dev 0 will imply all fees goes to the feeReceiver
    uint256 public polFeeCollectorFeeRate;

    /// @notice Mint rate of Honey for each asset, 60.18-decimal fixed-point number representation
    mapping(address asset => uint256 rate) internal mintRates;
    /// @notice Redemption rate of Honey for each asset, 60.18-decimal fixed-point number representation
    mapping(address asset => uint256 rate) internal redeemRates;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _governance,
        address _honey,
        address _feeReceiver,
        address _polFeeCollector
    )
        external
        initializer
    {
        __VaultAdmin_init(_governance, _feeReceiver, _polFeeCollector);
        honey = Honey(_honey);
        // initialize with 5e17, 50% of the mint/redeem fee goes to the polFeeCollector
        polFeeCollectorFeeRate = 5e17;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       MANAGER FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set the mint rate of Honey for an asset.
    function setMintRate(address asset, uint256 mintRate) external onlyRole(MANAGER_ROLE) {
        if (mintRate > ONE_HUNDRED_PERCENT_RATE) {
            OverOneHundredPercentRate.selector.revertWith(mintRate);
        }
        if (mintRate < NINETY_EIGHT_PERCENT_RATE) {
            UnderNinetyEightPercentRate.selector.revertWith(mintRate);
        }
        mintRates[asset] = mintRate;
        emit MintRateSet(asset, mintRate);
    }

    /// @notice Set the redemption rate of Honey for an asset.
    function setRedeemRate(address asset, uint256 redeemRate) external onlyRole(MANAGER_ROLE) {
        if (redeemRate > ONE_HUNDRED_PERCENT_RATE) {
            OverOneHundredPercentRate.selector.revertWith(redeemRate);
        }
        if (redeemRate < NINETY_EIGHT_PERCENT_RATE) {
            UnderNinetyEightPercentRate.selector.revertWith(redeemRate);
        }
        redeemRates[asset] = redeemRate;
        emit RedeemRateSet(asset, redeemRate);
    }

    function setPOLFeeCollectorFeeRate(uint256 _polFeeCollectorFeeRate) external onlyRole(MANAGER_ROLE) {
        if (_polFeeCollectorFeeRate > ONE_HUNDRED_PERCENT_RATE) {
            OverOneHundredPercentRate.selector.revertWith(_polFeeCollectorFeeRate);
        }
        polFeeCollectorFeeRate = _polFeeCollectorFeeRate;
        emit POLFeeCollectorFeeRateSet(_polFeeCollectorFeeRate);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Check the invariant of the vault to ensure that assets are always sufficient to redeem.
    modifier checkInvariants(address asset) {
        _;
        ERC4626 vault = vaults[asset];
        uint256 totalShares = vault.totalSupply();
        uint256 totalAssets = ERC20(asset).balanceOf(address(vault));
        if (vault.convertToAssets(totalShares) > totalAssets) {
            InsufficientAssets.selector.revertWith(totalAssets, totalShares);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IHoneyFactory
    function mint(
        address asset,
        uint256 amount,
        address receiver
    )
        external
        onlyRegisteredAsset(asset)
        onlyGoodCollateralAsset(asset)
        whenNotPaused
        checkInvariants(asset)
        returns (uint256)
    {
        ERC4626 vault = vaults[asset];
        // The sender transfers the assets into the factory.
        // The sender needs to approve the assets to the factory before calling this function.
        SafeTransferLib.safeTransferFrom(asset, msg.sender, address(this), amount);
        // The factory approves the Vault for the assets.
        SafeTransferLib.safeApprove(asset, address(vault), amount);
        // The factory deposits the assets into Vault to mint the corresponding amount of shares.
        uint256 shares = vault.deposit(amount, address(this));
        // The factory mints the corresponding amount of Honey to the receiver
        // with the consideration of the static mint fee.
        (uint256 honeyToMint, uint256 feeReceiverFeeShares, uint256 polFeeCollectorFeeShares) =
            _getHoneyMintedFromShares(asset, shares);
        // The mint fee is distributed to the fee receiver and the polFeeCollector.
        // Factory keeps the shares of fees until they are redeemed.
        collectedFees[feeReceiver][asset] += feeReceiverFeeShares;
        collectedFees[polFeeCollector][asset] += polFeeCollectorFeeShares;
        honey.mint(receiver, honeyToMint);
        emit HoneyMinted(msg.sender, receiver, asset, amount, honeyToMint);
        return honeyToMint;
    }

    /// @inheritdoc IHoneyFactory
    function redeem(
        address asset,
        uint256 honeyAmount,
        address receiver
    )
        external
        onlyRegisteredAsset(asset)
        whenNotPaused
        checkInvariants(asset)
        returns (uint256)
    {
        ERC4626 vault = vaults[asset];
        // The function reverts if the sender does not have enough Honey to burn or
        // the vault does not have enough assets to redeem.
        // The factory burns the corresponding amount of Honey of the sender
        // to get the shares and redeem them for assets from the vault.
        uint256 redeemedAssets;
        {
            (uint256 sharesForRedeem, uint256 feeReceiverFeeShares, uint256 polFeeCollectorFeeShares) =
                _getSharesRedeemedFromHoney(asset, honeyAmount);
            honey.burn(msg.sender, honeyAmount);
            // The redeem fee is distributed to the fee receiver and the polFeeCollector.
            // Factory keeps the shares of fees until they are redeemed.
            collectedFees[feeReceiver][asset] += feeReceiverFeeShares;
            collectedFees[polFeeCollector][asset] += polFeeCollectorFeeShares;
            // The factory redeems the corresponding amount of assets from Vault
            // and transfer the assets to the receiver.
            redeemedAssets = vault.redeem(sharesForRedeem, receiver, address(this));
        }
        emit HoneyRedeemed(msg.sender, receiver, asset, redeemedAssets, honeyAmount);
        return redeemedAssets;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IHoneyFactory
    function previewMint(address asset, uint256 amount) external view returns (uint256 honeyAmount) {
        ERC4626 vault = vaults[asset];
        // Get shares for a given assets.
        uint256 shares = vault.previewDeposit(amount);
        (honeyAmount,,) = _getHoneyMintedFromShares(asset, shares);
    }

    /// @inheritdoc IHoneyFactory
    function previewRedeem(address asset, uint256 honeyAmount) external view returns (uint256) {
        ERC4626 vault = vaults[asset];
        (uint256 shares,,) = _getSharesRedeemedFromHoney(asset, honeyAmount);
        // Get assets for a given shares.
        return vault.previewRedeem(shares);
    }

    /// @inheritdoc IHoneyFactory
    function previewRequiredCollateral(address asset, uint256 exactHoneyAmount) external view returns (uint256) {
        ERC4626 vault = vaults[asset];
        uint256 mintRate = _getMintRate(asset);
        UD60x18 shares = ud(exactHoneyAmount).div(ud(mintRate));
        // Get assets for an exact shares.
        return vault.previewMint(UD60x18.unwrap(shares));
    }

    /// @inheritdoc IHoneyFactory
    function previewHoneyToRedeem(address asset, uint256 exactAmount) external view returns (uint256) {
        ERC4626 vault = vaults[asset];
        // Get shares for an exact assets.
        uint256 shares = vault.previewWithdraw(exactAmount);
        uint256 redeemRate = _getRedeemRate(asset);
        UD60x18 honeyAmount = ud(shares).div(ud(redeemRate));
        return UD60x18.unwrap(honeyAmount);
    }

    /// @inheritdoc IHoneyFactory
    function getMintRate(address asset) external view returns (uint256) {
        return _getMintRate(asset);
    }

    /// @inheritdoc IHoneyFactory
    function getRedeemRate(address asset) external view returns (uint256) {
        return _getRedeemRate(asset);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getHoneyMintedFromShares(
        address asset,
        uint256 shares
    )
        internal
        view
        returns (uint256 honeyAmount, uint256 feeReceiverFeeShares, uint256 polFeeCollectorFeeShares)
    {
        uint256 mintRate = _getMintRate(asset);
        honeyAmount = ud(shares).mul(ud(mintRate)).unwrap();
        uint256 feeShares = shares - honeyAmount;
        polFeeCollectorFeeShares = ud(feeShares).mul(ud(polFeeCollectorFeeRate)).unwrap();
        feeReceiverFeeShares = feeShares - polFeeCollectorFeeShares;
    }

    function _getSharesRedeemedFromHoney(
        address asset,
        uint256 honeyAmount
    )
        internal
        view
        returns (uint256 shares, uint256 feeReceiverFeeShares, uint256 polFeeCollectorFeeShares)
    {
        uint256 redeemRate = _getRedeemRate(asset);
        shares = ud(honeyAmount).mul(ud(redeemRate)).unwrap();
        uint256 feeShares = honeyAmount - shares;
        polFeeCollectorFeeShares = ud(feeShares).mul(ud(polFeeCollectorFeeRate)).unwrap();
        feeReceiverFeeShares = feeShares - polFeeCollectorFeeShares;
    }

    function _getMintRate(address asset) internal view returns (uint256) {
        return mintRates[asset];
    }

    function _getRedeemRate(address asset) internal view returns (uint256) {
        return redeemRates[asset];
    }
}
