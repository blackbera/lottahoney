// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Script, console2 } from "forge-std/Script.sol";

import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import "../base/Storage.sol";

contract TransferHoneyOwnership is Storage, Script {
    address internal honeyFactoryManager;

    function run() public virtual {
        // Update these addresses with the desired contract addresses.
        honey = Honey(0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03);
        honeyFactory = HoneyFactory(0xAd1782b2a7020631249031618fB1Bd09CD926b31);
        timelock = 0xcB364028856f2328148Bb32f9D6E7a1F86451b1c;
        honeyFactoryManager = address(0x3);
        vm.startBroadcast();

        console2.log("Sender address: ", msg.sender);

        transferHoneyOwnership();
        transferHoneyFactoryOwnership();
        transferHoneyFactoryBeaconOwnership();

        vm.stopBroadcast();
    }

    // transfer ownership of Honey to timelock and revoke the default admin role from msg.sender
    function transferHoneyOwnership() internal {
        console2.log("Transferring ADMIN ROLE of Honey...");
        honey.grantRole(honey.DEFAULT_ADMIN_ROLE(), timelock);
        require(
            honey.hasRole(honey.DEFAULT_ADMIN_ROLE(), timelock), "Default admin role of Honey not granted to timelock"
        );
        console2.log("Default admin role of Honey granted to:", timelock);

        console2.log("Revoking ADMIN ROLE of Honey from msg.sender...");
        honey.revokeRole(honey.DEFAULT_ADMIN_ROLE(), msg.sender);
        require(
            !honey.hasRole(honey.DEFAULT_ADMIN_ROLE(), msg.sender),
            "Default admin role of Honey not revoked from msg.sender"
        );
        console2.log("Default admin role of Honey revoked from:", msg.sender);
    }

    // transfer ownership of HoneyFactory to timelock and set the manager role to honeyFactoryManager
    // also revoke the manager and default admin roles from msg.sender
    function transferHoneyFactoryOwnership() internal {
        console2.log("Transferring ADMIN ROLE of HoneyFactory...");
        honeyFactory.grantRole(honeyFactory.DEFAULT_ADMIN_ROLE(), timelock);
        require(
            honeyFactory.hasRole(honeyFactory.DEFAULT_ADMIN_ROLE(), timelock),
            "Default admin role of HoneyFactory not granted to timelock"
        );
        console2.log("Default admin role of HoneyFactory granted to:", timelock);

        honeyFactory.grantRole(honeyFactory.MANAGER_ROLE(), honeyFactoryManager);
        require(
            honeyFactory.hasRole(honeyFactory.MANAGER_ROLE(), honeyFactoryManager),
            "MANAGER_ROLE of HoneyFactory not granted to honeyFactoryManager"
        );
        console2.log("MANAGER_ROLE of HoneyFactory granted to:", honeyFactoryManager);

        console2.log("Revoking MANAGER ROLE of HoneyFactory from msg.sender...");
        honeyFactory.revokeRole(honeyFactory.MANAGER_ROLE(), msg.sender);
        require(
            !honeyFactory.hasRole(honeyFactory.MANAGER_ROLE(), msg.sender),
            "MANAGER_ROLE of HoneyFactory not revoked from msg.sender"
        );
        console2.log("MANAGER_ROLE of HoneyFactory revoked from:", msg.sender);

        console2.log("Revoking ADMIN ROLE of HoneyFactory from msg.sender...");
        honeyFactory.revokeRole(honeyFactory.DEFAULT_ADMIN_ROLE(), msg.sender);
        require(
            !honeyFactory.hasRole(honeyFactory.DEFAULT_ADMIN_ROLE(), msg.sender),
            "Default admin role not revoked from msg.sender"
        );
        console2.log("Default admin role revoked from:", msg.sender);
    }

    // transfer ownership of HoneyFactory's Beacon to timelock
    function transferHoneyFactoryBeaconOwnership() internal {
        console2.log("Transferring ownership of HoneyFactory's Beacon...");
        UpgradeableBeacon beacon = UpgradeableBeacon(honeyFactory.beacon());
        beacon.transferOwnership(timelock);
        require(beacon.owner() == timelock, "Ownership of HoneyFactory's Beacon not transferred to timelock");
        console2.log("Ownership of HoneyFactory's Beacon transferred to:", timelock);
    }
}
