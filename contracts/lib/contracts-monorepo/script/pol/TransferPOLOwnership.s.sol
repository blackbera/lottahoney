// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Script, console2 } from "forge-std/Script.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import "../base/Storage.sol";

contract TransferPOLOwnership is Storage, Script {
    function run() public virtual {
        // Update these addresses with the desired contract addresses.
        rewardsFactory = BerachainRewardsVaultFactory(0x2B6e40f65D82A0cB98795bC7587a71bfa49fBB2B);
        beraChef = BeraChef(0xfb81E39E3970076ab2693fA5C45A07Cc724C93c2);
        blockRewardController = BlockRewardController(0x696C296D320beF7b3148420bf2Ff4a378c0a209B);
        distributor = Distributor(0x2C1F148Ee973a4cdA4aBEce2241DF3D3337b7319);
        bgtStaker = BGTStaker(0x791fb53432eED7e2fbE4cf8526ab6feeA604Eb6d);
        feeCollector = FeeCollector(0x9B6F83a371Db1d6eB2eA9B33E84f3b6CB4cDe1bE);
        timelock = 0xcB364028856f2328148Bb32f9D6E7a1F86451b1c;

        vm.startBroadcast();

        console2.log("Sender address: ", msg.sender);

        console2.log("Transferring ownership of POL contracts...");
        transferPOLOwnership();

        console2.log("Transferring ownership of BGT fees contracts...");
        transferBGTFeesOwnership();

        vm.stopBroadcast();
    }

    function transferPOLOwnership() internal {
        console2.log("Transferring ownership of BGT...");
        bgt.transferOwnership(timelock);
        require(bgt.owner() == timelock, "Ownership transfer failed for BGT");
        console2.log("Ownership of BGT transferred to:", timelock);

        console2.log("Transferring ownership of BerachainRewardsVaultFactory...");
        rewardsFactory.grantRole(rewardsFactory.DEFAULT_ADMIN_ROLE(), timelock);
        require(
            rewardsFactory.hasRole(rewardsFactory.DEFAULT_ADMIN_ROLE(), timelock),
            "Default admin role of rewards factory not granted to timelock"
        );
        rewardsFactory.renounceRole(rewardsFactory.DEFAULT_ADMIN_ROLE(), msg.sender);
        require(
            !rewardsFactory.hasRole(rewardsFactory.DEFAULT_ADMIN_ROLE(), msg.sender),
            "Default admin role of rewards factory not revoked from msg.sender"
        );
        console2.log("Ownership of BerachainRewardsVaultFactory transferred to:", timelock);

        console2.log("Transferring ownership of BerachainRewardsVault's Beacon...");
        UpgradeableBeacon beacon = UpgradeableBeacon(rewardsFactory.beacon());
        beacon.transferOwnership(timelock);
        console2.log("Ownership of BerachainRewardsVault's Beacon transferred to:", timelock);

        console2.log("Transferring ownership of Berachef...");
        beraChef.transferOwnership(timelock);
        console2.log("Ownership of Berachef transferred to:", timelock);

        console2.log("Transferring ownership of BlockRewardController...");
        blockRewardController.transferOwnership(timelock);
        require(blockRewardController.owner() == timelock, "Ownership transfer failed for BlockRewardController");
        console2.log("Ownership of BlockRewardController transferred to:", timelock);

        console2.log("Transferring ownership of Distributor...");
        distributor.grantRole(distributor.DEFAULT_ADMIN_ROLE(), timelock);
        require(
            distributor.hasRole(distributor.DEFAULT_ADMIN_ROLE(), timelock),
            "Default admin role of Distributor not granted to timelock"
        );
        distributor.renounceRole(distributor.DEFAULT_ADMIN_ROLE(), msg.sender);
        require(
            !distributor.hasRole(distributor.DEFAULT_ADMIN_ROLE(), msg.sender),
            "Default admin role of Distributor not revoked from msg.sender"
        );
        console2.log("Ownership of Distributor transferred to:", timelock);
    }

    function transferBGTFeesOwnership() internal {
        console2.log("Transferring ownership of BGTStaker...");
        bgtStaker.transferOwnership(timelock);
        require(bgtStaker.owner() == timelock, "Ownership transfer failed for BGTStaker");
        console2.log("Ownership of BGTStaker transferred to:", timelock);

        console2.log("Transferring ownership of FeeCollector...");
        feeCollector.grantRole(feeCollector.DEFAULT_ADMIN_ROLE(), timelock);
        require(
            feeCollector.hasRole(feeCollector.DEFAULT_ADMIN_ROLE(), timelock),
            "Default admin role of FeeCollector not granted to timelock"
        );
        feeCollector.renounceRole(feeCollector.DEFAULT_ADMIN_ROLE(), msg.sender);
        require(
            !feeCollector.hasRole(feeCollector.DEFAULT_ADMIN_ROLE(), msg.sender),
            "Default admin role of FeeCollector not revoked from msg.sender"
        );
        console2.log("Ownership of FeeCollector transferred to:", timelock);
    }
}
