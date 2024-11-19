// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

library StorageUtils {
    /// Returns bytes32 key for a trader's trade/limit count
    /// @param trader the address of the trader
    /// @param pairIndex the trade or order's pair index
    /// @return key bytes32 key for a mapping
    function traderCountKeyFor(address trader, uint256 pairIndex) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(trader, pairIndex));
    }

    /// Returns whether a pair is listed given the from/to currencies
    /// @param self The mapping containing all the listed pairs
    /// @param from the from currency of the pair
    /// @param to the to currency of the pair
    /// @return exists whether the pair is listed
    function get(
        mapping(bytes32 => bool) storage self,
        string memory from,
        string memory to
    )
        internal
        view
        returns (bool)
    {
        return self[keccak256(abi.encodePacked(from, to))];
    }

    /// Sets a pair to be listed for the given from/to currencies
    /// @param self The mapping containing all the listed pairs
    /// @param from the from currency of the pair
    /// @param to the to currency of the pair
    function set(mapping(bytes32 => bool) storage self, string memory from, string memory to) internal {
        self[keccak256(abi.encodePacked(from, to))] = true;
    }
}
