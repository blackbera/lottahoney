// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { LotteryVault } from "../src/LotteryVault.sol";
import { PrzHoney } from "../src/PrzHoney.sol";
import { BerachainGovernance } from "contracts-monorepo/gov/BerachainGovernance.sol";
import { IBerachainRewardsVaultFactory } from "contracts-monorepo/pol/interfaces/IBerachainRewardsVaultFactory.sol";
import { IBerachainRewardsVault } from "contracts-monorepo/pol/interfaces/IBerachainRewardsVault.sol";
import { IBeraChef } from "contracts-monorepo/pol/interfaces/IBeraChef.sol";
import {console} from "forge-std/console.sol";

contract LocalSetup is Script {
    // Existing Berachain Addresses
    address public constant HONEY = 0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03;
    address public constant GOVERNANCE = 0xE3EDa03401Cf32010a9A9967DaBAEe47ed0E1a0b;
    address public constant REWARDS_VAULT_FACTORY = 0x2B6e40f65D82A0cB98795bC7587a71bfa49fBB2B;
    address public constant BERACHEF = 0xfb81E39E3970076ab2693fA5C45A07Cc724C93c2;
    address public constant TIMELOCK = 0xcB364028856f2328148Bb32f9D6E7a1F86451b1c;
    address public constant HONEY_WHALE = 0xCe67E15cbCb3486B29aD44486c5B5d32f361fdDc;

    // Pyth Entropy Addresses
    address public constant ENTROPY_SERVICE = 0x36825bf3Fbdf5a29E2d5148bfe7Dcf7B5639e320;
    address public constant DEFAULT_PROVIDER = 0x6CC14824Ea2918f5De5C2f75A9Da968ad4BD6344;

    // Our contracts
    LotteryVault public lotteryVault;
    PrzHoney public przHoney;
    IBerachainRewardsVault public rewardsVault;

    // Our addresses
    address public operator;
    address public owner;

    function setUp() public {
        // Start broadcasting
        vm.startBroadcast();

        // Setup our addresses
        operator = makeAddr("operator");
        owner = makeAddr("owner");
        vm.deal(owner, 100 ether);      // Fund owner with BERA
        vm.deal(HONEY_WHALE, 100 ether); // Fund HONEY_WHALE with BERA for governance
        vm.deal(TIMELOCK, 100 ether);    // Fund TIMELOCK with BERA for whitelisting

        // Deploy PrzHoney
        przHoney = new PrzHoney(owner);

        // Create rewards vault using existing factory
        IBerachainRewardsVaultFactory factory = IBerachainRewardsVaultFactory(REWARDS_VAULT_FACTORY);
        address vaultAddress = factory.createRewardsVault(address(przHoney));
        rewardsVault = IBerachainRewardsVault(vaultAddress);

        vm.stopBroadcast();
        
        // Start broadcast as TIMELOCK for permissions
        vm.startBroadcast(TIMELOCK);
        
        // Add vault as friend of BeraChef directly
        IBeraChef(BERACHEF).updateFriendsOfTheChef(address(rewardsVault), true);
        console.log("[OK] Rewards vault added to BeraChef friends");
        
        // Whitelist HONEY as incentive token
        rewardsVault.whitelistIncentiveToken(HONEY, 1);
        console.log("[OK] HONEY whitelisted as incentive token in rewards vault");
        
        vm.stopBroadcast();
        
        // Start broadcast as owner for deployments and setup
        vm.startBroadcast(owner);

        // Deploy LotteryVault with Pyth parameters
        lotteryVault = new LotteryVault(
            HONEY,
            owner,
            address(rewardsVault),
            operator,
            ENTROPY_SERVICE,
            DEFAULT_PROVIDER
        );

        // Fund lottery vault with extra BERA for entropy fees
        (bool success,) = address(lotteryVault).call{value: 20 ether}(""); // Increased from 10 to 20 ETH
        require(success, "BERA transfer failed");

        // Setup PrzHoney ownership
        przHoney.transferOwnership(address(lotteryVault));

        // Set PrzHoney in lottery vault
        lotteryVault.setPrzHoney(address(przHoney));

        vm.stopBroadcast();

        // Log deployed addresses
        console.log("Deployed addresses:");
        console.log("LotteryVault:", address(lotteryVault));
        console.log("PrzHoney:", address(przHoney));
        console.log("RewardsVault:", address(rewardsVault));
        console.log("Entropy Service:", ENTROPY_SERVICE);
        console.log("Default Provider:", DEFAULT_PROVIDER);
    }

    function run() public {
        console.log("\n=== Please copy these addresses to your .env file ===");
        console.log("LOTTERY_VAULT_ADDRESS=", address(lotteryVault));
        console.log("PRZ_HONEY_ADDRESS=", address(przHoney));
        console.log("REWARDS_VAULT_ADDRESS=", address(rewardsVault));
        console.log("ENTROPY_ADDRESS=", ENTROPY_SERVICE);
        console.log("PROVIDER_ADDRESS=", DEFAULT_PROVIDER);
        console.log("================================================\n");
    }
}