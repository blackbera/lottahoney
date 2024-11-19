// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// NOTE: currently this mock is only used by Referrals test.
import { IOrdersForReferrals } from "src/berps/core/v0/Referrals.sol";

contract MockOrders is IOrdersForReferrals {
    address public settlement;
    address public gov;

    mapping(address => uint256) public balanceOf;

    constructor(address _settlement, address _gov) {
        settlement = _settlement;
        gov = _gov;
    }

    function transferHoney(address from, address to, uint256 amount) external {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    function setBalance(address addr, uint256 amount) external {
        balanceOf[addr] = amount;
    }
}
