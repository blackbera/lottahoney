// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Script, console2 } from "forge-std/Script.sol";

import { ERC4626 } from "solady/src/tokens/ERC4626.sol";

import { Honey } from "src/honey/Honey.sol";
import { CollateralVault } from "src/honey/CollateralVault.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { HoneyDeployer } from "src/honey/HoneyDeployer.sol";

import { USDC } from "../misc/USDC.sol";
import { MintHoney } from "./MintHoney.s.sol";
import { AddCollateral } from "./AddCollateral.s.sol";

contract DeployHoney is Script, MintHoney, AddCollateral {
    HoneyDeployer internal honeyDeployer;
    // placeholder for fee receiver, change before deployment
    address internal feeReceiver = address(0x1);
    // placeholder for polFeeCollector, change before deployment
    address internal polFeeCollector = address(0x2);

    // amount of USDC to deposit for minting Honey, 100 USDC
    uint256 internal constant USDC_DEPOSIT_AMOUNT = 100e6;
    // amount of PYUSD to deposit for minting Honey, 100 PYUSD
    uint256 internal constant PYUSD_DEPOSIT_AMOUNT = 100e6;

    uint256 internal constant HONEY_SALT = 0;
    uint256 internal constant HONEY_FACTORY_SALT = 1;

    function run() public virtual override(MintHoney, AddCollateral) {
        vm.startBroadcast();

        console2.log("Sender address: ", msg.sender);
        deployHoney();

        // requires MANAGER_ROLE to be granted to msg.sender
        addCollateral(usdc);
        addCollateral(pyusd);

        // minting Honey
        mintHoney(usdc, USDC_DEPOSIT_AMOUNT, msg.sender);
        mintHoney(pyusd, PYUSD_DEPOSIT_AMOUNT, msg.sender);

        vm.stopBroadcast();
    }

    function deployHoney() internal {
        console2.log("Deploying Honey and HoneyFactory...");
        honeyDeployer = new HoneyDeployer(msg.sender, feeReceiver, polFeeCollector, HONEY_SALT, HONEY_FACTORY_SALT);

        console2.log("HoneyDeployer deployed at:", address(honeyDeployer));

        honey = honeyDeployer.honey();
        honeyFactory = honeyDeployer.honeyFactory();

        console2.log("Honey deployed at:", address(honey));
        console2.log("HoneyFactory deployed at:", address(honeyFactory));

        require(honeyFactory.feeReceiver() == feeReceiver, "Fee receiver not set");
        console2.log("Fee receiver set to:", feeReceiver);

        require(honeyFactory.polFeeCollector() == polFeeCollector, "Pol fee collector not set");
        console2.log("Pol fee collector set to:", polFeeCollector);

        // check roles and grant manager role to msg.sender.
        require(
            honey.hasRole(honey.DEFAULT_ADMIN_ROLE(), msg.sender),
            "Honey's DEFAULT_ADMIN_ROLE not granted to msg.sender"
        );
        console2.log("Honey's DEFAULT_ADMIN_ROLE granted to:", msg.sender);

        require(
            honeyFactory.hasRole(honeyFactory.DEFAULT_ADMIN_ROLE(), msg.sender),
            "HoneyFactory's DEFAULT_ADMIN_ROLE not granted to msg.sender"
        );
        console2.log("HoneyFactory's DEFAULT_ADMIN_ROLE granted to:", msg.sender);

        // granting MANAGER_ROLE to msg.sender as we need to call
        // setMintRate and setRedeemRate while doing `addCollateral`
        honeyFactory.grantRole(honeyFactory.MANAGER_ROLE(), msg.sender);

        require(
            honeyFactory.hasRole(honeyFactory.MANAGER_ROLE(), msg.sender),
            "HoneyFactory's MANAGER_ROLE not granted to msg.sender"
        );
        console2.log("HoneyFactory's MANAGER_ROLE granted to:", msg.sender);
    }
}
