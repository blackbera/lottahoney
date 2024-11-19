// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { Ownable } from "solady/src/auth/Ownable.sol";

contract DAI is ERC20, Ownable {
    string private constant _name = "Decentralized USD";
    string private constant _symbol = "DAI";

    constructor() {
        _initializeOwner(msg.sender);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    function name() public pure override returns (string memory) {
        return _name;
    }

    function symbol() public pure override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}