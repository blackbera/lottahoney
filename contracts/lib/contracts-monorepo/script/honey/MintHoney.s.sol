// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Script, console2 } from "forge-std/Script.sol";

import { ERC20 } from "solady/src/tokens/ERC20.sol";

import { USDC } from "../misc/USDC.sol";
import "../base/Storage.sol";

contract MintHoney is Storage, Script {
    uint256 internal constant AMOUNT = 1e10 * 1e6;
    // Placeholder for USDC and PayPal USD stable coins
    address internal usdc = 0xd6D83aF58a19Cd14eF3CF6fe848C9A4d21e5727c;
    address internal pyusd = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;

    function run() public virtual {
        honey = Honey(0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03);
        honeyFactory = HoneyFactory(0xAd1782b2a7020631249031618fB1Bd09CD926b31);
        vm.startBroadcast();

        console2.log("Sender address: ", msg.sender);

        USDC(usdc).mint(msg.sender, AMOUNT);
        console2.log("Minted %d USDC to %s", AMOUNT, msg.sender);

        mintHoney(usdc, AMOUNT, msg.sender);

        console2.log("Honey balance of %s: %d", msg.sender, honey.balanceOf(msg.sender));

        vm.stopBroadcast();
    }

    function mintHoney(address collateral, uint256 amount, address to) internal returns (uint256 mintedAmount) {
        ERC20(collateral).approve(address(honeyFactory), amount);
        console2.log("Approved %d tokens for honeyFactory", amount);

        mintedAmount = honeyFactory.mint(collateral, amount, to);
        console2.log("Minted %d Honey to %s", mintedAmount, to);
    }
}
