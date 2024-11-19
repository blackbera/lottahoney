// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { BerachainRewardsVault } from "src/pol/rewards/BerachainRewardsVault.sol";

contract AddIncentive is Script {
    BerachainRewardsVault internal constant REWARDS_VAULT =
        BerachainRewardsVault(0xc1Cc17c027f3BDDFd708BfD6E77c6e13DF80BF10);
    address internal constant incentiveToken = 0x09f1f426481F50d704FFEd89B41b3138E4ba53db;
    uint256 internal constant incentiveRate = 1 gwei;
    uint256 internal constant incentiveAmount = 1e5 ether;

    function run() public virtual {
        vm.startBroadcast();

        console2.log("Sender address: ", msg.sender);

        console2.log("Adding incentives to rewards vault %s", address(REWARDS_VAULT));
        addIncentive(REWARDS_VAULT, incentiveToken, incentiveAmount, incentiveRate);

        vm.stopBroadcast();
    }

    function addIncentive(BerachainRewardsVault vault, address token, uint256 amount, uint256 rate) internal {
        // Whitelist the incentive token if necessary.
        whitelistIncentiveTokenIfNecessary(vault, token, rate);

        // Approve the rewards vault to spend the incentive token.
        IERC20(token).approve(address(vault), amount);
        console2.log("Approved %d tokens for rewards vault", amount);

        // Add the incentive to the rewards vault.
        vault.addIncentive(token, amount, rate);
        console2.log("Added %d tokens as incentive to rewards vault", amount);
    }

    function whitelistIncentiveTokenIfNecessary(
        BerachainRewardsVault vault,
        address token,
        uint256 minIncentiveRate
    )
        internal
    {
        address[] memory whitelistedTokens = vault.getWhitelistedTokens();
        for (uint256 i; i < whitelistedTokens.length; ++i) {
            if (whitelistedTokens[i] == token) {
                return;
            }
        }
        vault.whitelistIncentiveToken(token, minIncentiveRate);
        console2.log("Whitelisted incentive token %s for rewards vault", token);
    }
}
