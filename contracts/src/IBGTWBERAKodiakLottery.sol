// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { BGTTogetherVault } from "./BGTTogetherVault.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract IBGTWBERAKodiakLottery is BGTTogetherVault {
    address public constant IBGT_WBERA = 0x7fd165B73775884a38AA8f2B384A53A3Ca7400E6;

    constructor(
        address _rewardsVault
    ) BGTTogetherVault(
        IBGT_WBERA,
        _rewardsVault,
        "przIBGTWBERA",
        "przIBGTWBERA"
    ) {}

    function deposit(uint256 amount) external returns (uint256 shares) {
        IERC20(IBGT_WBERA).transferFrom(msg.sender, address(this), amount);
        shares = depositReceiptTokens(amount);
        emit Deposit(msg.sender, amount, shares);
    }

    function withdraw(uint256 amount) external returns (uint256 shares) {
        shares = withdrawReceiptTokens(amount);
        IERC20(IBGT_WBERA).transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount, shares);
    }

    event Deposit(address indexed user, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 amount, uint256 shares);
} 