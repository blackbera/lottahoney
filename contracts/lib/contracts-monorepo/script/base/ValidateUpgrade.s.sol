// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Script, console2 } from "forge-std/Script.sol";
import { Upgrades, Options } from "openzeppelin-foundry-upgrades/Upgrades.sol";

/// @notice This script is used to validate the upgrade of any upgradeable contract.
/// @dev This will fail if any storage collisions are detected.
/// @dev Need to run forge clean && forge compile before running this script.
contract ValidateUpgrade is Script {
    function run() public {
        vm.startBroadcast();
        // To validate the upgrade, we need to provide the upgraded contract name and the options
        // Either contract name should point to the deployed contract that is being upgraded using
        // @custom:oz-upgrades-from ContractV1
        // or `referenceContract` should be specified in the Options object.
        Options memory options; // create an empty options object.
        // use below if ContractV2 does not have upgrades-from annotation.
        // options.referenceContract = "ContractV1"; // specify the reference contract name.
        Upgrades.validateUpgrade("ContractV2.sol", options);
        console2.log("contract can be upgraded successfully.");
        vm.stopBroadcast();
    }
}
