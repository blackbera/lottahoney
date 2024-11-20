// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { LotteryVault } from "../src/LotteryVault.sol";
import { PrzHoney } from "../src/PrzHoney.sol";
import { IBerachainRewardsVaultFactory } from "contracts-monorepo/pol/interfaces/IBerachainRewardsVaultFactory.sol";
import { console } from "forge-std/console.sol";

/**
 * @title Deploy
 * @notice Deployment script for LotteryVault system on Berachain Artio testnet
 */
contract Deploy is Script {
    // Berachain Artio Addresses
    address public constant HONEY = 0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03;
    address public constant REWARDS_VAULT_FACTORY = 0x2B6e40f65D82A0cB98795bC7587a71bfa49fBB2B;
    
    // Pyth Addresses
    address public constant ENTROPY_SERVICE = 0x36825bf3Fbdf5a29E2d5148bfe7Dcf7B5639e320;
    address public constant DEFAULT_PROVIDER = 0x6CC14824Ea2918f5De5C2f75A9Da968ad4BD6344;

    function run() external {
        // Get deployer details from .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("\n=== Starting Deployment ===");
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy PrzHoney (initially owned by deployer)
        PrzHoney przHoney = new PrzHoney(deployer);
        console.log("PrzHoney deployed to:", address(przHoney));

        // 2. Create rewards vault using factory
        IBerachainRewardsVaultFactory factory = IBerachainRewardsVaultFactory(REWARDS_VAULT_FACTORY);
        address rewardsVault = factory.createRewardsVault(address(przHoney));
        console.log("RewardsVault created at:", rewardsVault);

        // 3. Deploy LotteryVault
        LotteryVault lotteryVault = new LotteryVault(
            HONEY,
            deployer,
            rewardsVault,
            ENTROPY_SERVICE,
            DEFAULT_PROVIDER
        );
        console.log("LotteryVault deployed to:", address(lotteryVault));

        // 4. Fund lottery vault with BERA for entropy fees
        (bool success,) = address(lotteryVault).call{value: 1 ether}("");
        require(success, "Failed to fund lottery vault");
        console.log("Funded LotteryVault with 1 BERA");

        // 5. Set PrzHoney in lottery vault
        lotteryVault.setPrzHoney(address(przHoney));
        console.log("Set PrzHoney in LotteryVault");

        // 6. Transfer PrzHoney ownership to LotteryVault
        przHoney.transferOwnership(address(lotteryVault));
        console.log("Transferred PrzHoney ownership to LotteryVault");

        vm.stopBroadcast();

        // Log final deployment information
        console.log("\n=== Deployment Summary ===");
        console.log("LotteryVault:", address(lotteryVault));
        console.log("PrzHoney:", address(przHoney));
        console.log("RewardsVault:", rewardsVault);
        console.log("\nAdd these addresses to your .env file:");
        console.log("LOTTERY_VAULT_ADDRESS=", address(lotteryVault));
        console.log("PRZ_HONEY_ADDRESS=", address(przHoney));
        console.log("REWARDS_VAULT_ADDRESS=", rewardsVault);
        console.log("=========================\n");
    }
}