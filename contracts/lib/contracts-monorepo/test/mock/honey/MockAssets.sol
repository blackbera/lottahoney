// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { ERC20 } from "solady/src/tokens/ERC20.sol";

contract MockDAI is ERC20 {
    string private constant _name = "MockDAI";
    string private constant _symbol = "DAI";

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function name() public pure override returns (string memory) {
        return _name;
    }

    function symbol() public pure override returns (string memory) {
        return _symbol;
    }
}

contract MockUSDT is ERC20 {
    string private constant _name = "MockUSDT";
    string private constant _symbol = "USDT";

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function name() public pure override returns (string memory) {
        return _name;
    }

    function symbol() public pure override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MockDummy is ERC20 {
    string private constant _name = "MockDummy";
    string private constant _symbol = "DUMMY";

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function name() public pure override returns (string memory) {
        return _name;
    }

    function symbol() public pure override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return 20;
    }
}
