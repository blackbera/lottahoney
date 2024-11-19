// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { console2 } from "forge-std/Script.sol";

import { AddIncentive } from "./AddIncentive.s.sol";
import "../base/Storage.sol";

contract DeployRewardsVault is Storage, AddIncentive {
    address[] internal STAKING_TOKENS = [
        0x1339503343be5626B40Ee3Aee12a4DF50Aa4C0B9,
        0xd28d852cbcc68DCEC922f6d5C7a8185dBaa104B7,
        0x917Bb6c98D5FE6177c78eA21E0dD94175e175Dca
    ];

    function run() public virtual override {
        beraChef = BeraChef(0xfb81E39E3970076ab2693fA5C45A07Cc724C93c2);
        rewardsFactory = BerachainRewardsVaultFactory(0x2B6e40f65D82A0cB98795bC7587a71bfa49fBB2B);
        wbera = WBERA(payable(0x7507c1dc16935B82698e4C63f2746A2fCf994dF8));
        address honey = 0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03;

        vm.startBroadcast();

        console2.log("Sender address: ", msg.sender);

        BerachainRewardsVault[] memory vaults = deployRewardsVaults(STAKING_TOKENS);
        configRewardsVaults(vaults);

        for (uint256 i; i < vaults.length; ++i) {
            addIncentive(vaults[i], honey, 1e5 ether, 1 ether);
            console2.log("Added %d HONEY incentive to Rewards Vault at rate %d", 1e5 ether, 1 ether);
        }

        vm.stopBroadcast();
    }

    /// @dev Deploy the rewards vault
    function deployRewardsVault(address stakingToken) internal returns (BerachainRewardsVault vault) {
        vault = BerachainRewardsVault(rewardsFactory.getVault(stakingToken));
        if (address(vault) != address(0)) {
            console2.log("Rewards vault for staking token %s already exists", stakingToken);
            return vault;
        }
        vault = BerachainRewardsVault(rewardsFactory.createRewardsVault(stakingToken));
        console2.log("BerachainRewardsVault deployed at %s for staking token %s", address(vault), stakingToken);
    }

    function deployRewardsVaults(address[] memory stakingTokens)
        internal
        returns (BerachainRewardsVault[] memory vaults)
    {
        vaults = new BerachainRewardsVault[](stakingTokens.length);
        for (uint256 i; i < stakingTokens.length; ++i) {
            vaults[i] = deployRewardsVault(stakingTokens[i]);
        }
    }

    /// @dev Whitelist and configure the rewards vault
    function configRewardsVault(address vault) internal {
        BerachainRewardsVault[] memory vaults = new BerachainRewardsVault[](1);
        vaults[0] = BerachainRewardsVault(vault);
        configRewardsVaults(vaults);
    }

    /// @dev Whitelist and configure the rewards vaults
    function configRewardsVaults(BerachainRewardsVault[] memory vaults) internal {
        uint96[] memory _weights = new uint96[](vaults.length);
        for (uint256 i; i < vaults.length; ++i) {
            _weights[i] = 10_000;
        }
        normalizeWeights(_weights, vaults.length);
        // setup the cutting board and vault for the stake token
        IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](vaults.length);
        for (uint256 i; i < vaults.length; ++i) {
            weights[i] = IBeraChef.Weight(address(vaults[i]), _weights[i]);
            if (beraChef.isFriendOfTheChef(address(vaults[i]))) {
                console2.log("Rewards Vault %s is already a friend of the chef", address(vaults[i]));
                continue;
            }
            beraChef.updateFriendsOfTheChef(address(vaults[i]), true);
            console2.log("Whitelisted %s as a friend of the chef", address(vaults[i]));
        }
        beraChef.setDefaultCuttingBoard(IBeraChef.CuttingBoard(1, weights));
        console2.log("Set the default cutting board");
    }

    function normalizeWeights(uint96[] memory weights, uint256 numVaults) internal pure {
        uint96 totalWeight = 0;
        for (uint256 i; i < numVaults; ++i) {
            totalWeight += weights[i];
        }

        // Check if totalWeight is already 10000 to avoid division if not necessary
        if (totalWeight != 10_000) {
            for (uint256 i; i < numVaults; ++i) {
                // Adjust each weight proportionally
                weights[i] = uint96((uint256(weights[i]) * 10_000) / totalWeight);
            }
        }

        // Ensure that the total exactly adds up to 10000 due to integer division adjustments
        uint96 correctedTotal = 0;
        for (uint256 i; i < numVaults; ++i) {
            correctedTotal += weights[i];
        }

        if (correctedTotal != 10_000) {
            // Adjust the last weight to make the sum exactly 10000
            weights[numVaults - 1] = weights[numVaults - 1] + 10_000 - correctedTotal;
        }
    }
}
