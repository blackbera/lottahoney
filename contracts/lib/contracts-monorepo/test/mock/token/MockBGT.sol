// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    ERC20Upgradeable,
    IERC20,
    IERC20Metadata
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20VotesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MockBGT is ERC20VotesUpgradeable, OwnableUpgradeable {
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __ERC20_init("BGT", "BGT");
    }

    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }
}