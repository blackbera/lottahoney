// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

/**
 * @notice This is a mock ERC4626 vault for testing.
 * @author Berachain Team
 * @author Solady (https://github.com/Vectorized/solady/tree/main/src/tokens/ERC4626.sol)
 * @author OpenZeppelin
 * (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol)
 */
contract FaultyVault {
    string private _name;
    address private _vaultAsset; // storage collision of _vaultAsset with name.
    string private _symbol;
    string private _newName;

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function setNewName(string memory newName) public {
        _newName = newName;
    }

    function getNewName() public view returns (string memory) {
        return _newName;
    }

    function asset() public view returns (address) {
        return _vaultAsset;
    }
}

contract MockVault {
    address private _vaultAsset;
    string private _name;
    string private _symbol;
    string private _newName;

    function VERSION() public pure returns (uint256) {
        return 2;
    }

    function isNewImplementation() public pure returns (bool) {
        return true;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function setNewName(string memory newName) public {
        _newName = newName;
    }

    function getNewName() public view returns (string memory) {
        return _newName;
    }

    function asset() public view returns (address) {
        return _vaultAsset;
    }
}
