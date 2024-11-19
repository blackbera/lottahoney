// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @notice Contains Pyth EVM Stable Price Feeds (https://pyth.network/developers/price-feed-ids)
/// @dev Add more price feeds as needed.
library PythFeeds {
    bytes32 public constant USDC_USD = bytes32(0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a);
    bytes32 public constant BTC_USD = bytes32(0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43);
    bytes32 public constant ETH_USD = bytes32(0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace);
    bytes32 public constant ATOM_USD = bytes32(0xb00b60f88b03a6a625a8d1c048c3f66653edf217439983d037e7222c4e612819);
    bytes32 public constant TIA_USD = bytes32(0x09f7c1d7dfbb7df2b8fe3d3d87ee94a2259d212da4f30c1f0540d066dfa44723);

    // TODO: Update this with the correct Honey price feed ID.
    // Right now it uses the USDC_USD feed, but should be replaced with HONEY_USD once available.
    bytes32 public constant HONEY_USD = bytes32(0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a);
}
