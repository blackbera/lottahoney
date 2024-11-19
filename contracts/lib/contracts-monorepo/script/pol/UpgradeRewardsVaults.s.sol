// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Script, console2 } from "forge-std/Script.sol";

import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import "../base/Storage.sol";

contract UpgradeRewardsVaults is Storage, Script {
    function run() public virtual {
        rewardsFactory = BerachainRewardsVaultFactory(0x307EF430EF37ca19d69a4A843F0D8e130295cEE1);

        vm.startBroadcast();

        console2.log("Sender address: ", msg.sender);

        Distributor distributor = Distributor(rewardsFactory.distributor());

        console2.log("distributor: ", address(distributor));

        console2.log("currentBlock: ", block.number);
        console2.log("lastActionedBlock: ", distributor.getLastActionedBlock());

        upgradeRewardsVaults(rewardsFactory);

        vm.stopBroadcast();
    }

    function upgradeRewardsVaults(BerachainRewardsVaultFactory _rewardsFactory) internal {
        UpgradeableBeacon beacon = UpgradeableBeacon(_rewardsFactory.beacon());
        console2.log("Beacon address: ", address(beacon));
        beacon.upgradeTo(address(new BerachainRewardsVault()));
        console2.log("Upgraded to: ", beacon.implementation());
    }
}
