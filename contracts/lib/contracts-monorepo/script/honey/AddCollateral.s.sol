// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { console2 } from "forge-std/Script.sol";

import { ERC4626 } from "solady/src/tokens/ERC4626.sol";

import { MintHoney } from "./MintHoney.s.sol";
import { USDT } from "../misc/USDT.sol";
import { DAI } from "../misc/DAI.sol";

contract AddCollateral is MintHoney {
    uint256 internal constant TOTAL_SUPPLY = 1e9;
    uint256 internal constant MINT_RATE = 0.995e18;
    uint256 internal constant REDEEM_RATE = 0.995e18;

    function run() public virtual override {
        vm.startBroadcast();

        console2.log("Sender address: ", msg.sender);

        console2.log("Deploying USDT...");
        USDT usdt = new USDT();
        console2.log("USDT deployed at:", address(usdt));
        uint256 mintAmount = TOTAL_SUPPLY * 10 ** usdt.decimals();
        usdt.mint(msg.sender, mintAmount);
        console2.log("Minted %d USDT to %s", mintAmount, msg.sender);
        addCollateral(address(usdt));

        console2.log("Deploying DAI...");
        DAI dai = new DAI();
        console2.log("DAI deployed at:", address(dai));
        mintAmount = TOTAL_SUPPLY * 10 ** dai.decimals();
        dai.mint(msg.sender, mintAmount);
        console2.log("Minted %d DAI to %s", mintAmount, msg.sender);
        addCollateral(address(dai));

        vm.stopBroadcast();
    }

    function addCollateral(address collateral) internal {
        console2.log("Adding collateral %s", collateral);
        ERC4626 vault = honeyFactory.createVault(collateral);
        console2.log("Collateral Vault deployed at:", address(vault));
        honeyFactory.setMintRate(collateral, MINT_RATE);
        console2.log("Mint rate set to %d", MINT_RATE);
        honeyFactory.setRedeemRate(collateral, REDEEM_RATE);
        console2.log("Redeem rate set to %d", REDEEM_RATE);
    }
}
