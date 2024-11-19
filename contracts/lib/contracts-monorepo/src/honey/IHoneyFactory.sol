// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @notice This is the interface of HoneyFactory.
/// @author Berachain Team
interface IHoneyFactory {
    /// @notice Emitted when a mint rate is set for an asset.
    event MintRateSet(address indexed asset, uint256 rate);

    /// @notice Emitted when a redemption rate is set for an asset.
    event RedeemRateSet(address indexed asset, uint256 rate);

    /// @notice Emitted when the POLFeeCollector fee rate is set.
    event POLFeeCollectorFeeRateSet(uint256 rate);

    /// @notice Emitted when honey is minted
    /// @param from The account that supplied assets for the minted honey.
    /// @param to The account that received the honey.
    /// @param asset The asset used to mint the honey.
    /// @param assetAmount The amount of assets supplied for minting the honey.
    /// @param mintAmount The amount of honey that was minted.
    event HoneyMinted(
        address indexed from, address indexed to, address indexed asset, uint256 assetAmount, uint256 mintAmount
    );

    /// @notice Emitted when honey is redeemed
    /// @param from The account that redeemed the honey.
    /// @param to The account that received the assets.
    /// @param asset The asset for redeeming the honey.
    /// @param assetAmount The amount of assets received for redeeming the honey.
    /// @param redeemAmount The amount of honey that was redeemed.
    event HoneyRedeemed(
        address indexed from, address indexed to, address indexed asset, uint256 assetAmount, uint256 redeemAmount
    );

    /// @notice Mint Honey by sending ERC20 to this contract.
    /// @dev Assest must be registered and must be a good collateral.
    /// @param amount The amount of ERC20 to mint with.
    /// @param receiver The address that will receive Honey.
    /// @return The amount of Honey minted.
    function mint(address asset, uint256 amount, address receiver) external returns (uint256);

    /// @notice Redeem assets by sending Honey in to burn.
    /// @param honeyAmount The amount of Honey to redeem.
    /// @param receiver The address that will receive assets.
    /// @return The amount of assets redeemed.
    function redeem(address asset, uint256 honeyAmount, address receiver) external returns (uint256);

    /// @notice Previews the amount of honey required to redeem an exact amount of target ERC20 asset.
    /// @param asset The ERC20 asset to receive.
    /// @param exactAmount The exact amount of assets to receive.
    function previewHoneyToRedeem(address asset, uint256 exactAmount) external view returns (uint256);

    /// @notice Get the amount of Honey that can be minted with the given ERC20.
    /// @param asset The ERC20 to mint with.
    /// @param amount The amount of ERC20 to mint with.
    /// @return The amount of Honey that can be minted.
    function previewMint(address asset, uint256 amount) external view returns (uint256);

    /// @notice Get the amount of ERC20 that can be redeemed with the given Honey.
    /// @param asset The ERC20 to redeem.
    /// @param honeyAmount The amount of Honey to redeem.
    /// @return The amount of ERC20 that can be redeemed.
    function previewRedeem(address asset, uint256 honeyAmount) external view returns (uint256);

    /// @notice Previews the amount of ERC20 required to mint an exact amount of honey.
    /// @param asset The ERC20 asset to use.
    /// @param exactHoneyAmount The exact amount of honey to mint.
    function previewRequiredCollateral(address asset, uint256 exactHoneyAmount) external view returns (uint256);

    /// @notice Get the mint rate of the asset.
    /// @param asset The ERC20 asset to get the mint rate.
    /// @return The mint rate of the asset.
    function getMintRate(address asset) external view returns (uint256);

    /// @notice Get the redeem rate of the asset.
    /// @param asset The ERC20 asset to get the redeem rate.
    /// @return The redeem rate of the asset.
    function getRedeemRate(address asset) external view returns (uint256);
}
