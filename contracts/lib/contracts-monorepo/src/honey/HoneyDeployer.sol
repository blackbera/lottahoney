// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { LibClone } from "solady/src/utils/LibClone.sol";

import { Create2Deployer } from "../base/Create2Deployer.sol";
import { Honey } from "./Honey.sol";
import { HoneyFactory } from "./HoneyFactory.sol";

/// @title HoneyDeployer
/// @author Berachain Team
/// @notice The HoneyDeployer contract is responsible for deploying the Honey contracts.
contract HoneyDeployer is Create2Deployer {
    /// @notice The Honey contract.
    // solhint-disable-next-line immutable-vars-naming
    Honey public immutable honey;

    /// @notice The HoneyFactory contract.
    // solhint-disable-next-line immutable-vars-naming
    HoneyFactory public immutable honeyFactory;

    constructor(
        address governance,
        address feeReceiver,
        address polFeeCollector,
        uint256 honeySalt,
        uint256 honeyFactorySalt
    ) {
        // deploy the Honey implementation
        address honeyImpl = deployWithCreate2(0, type(Honey).creationCode);
        // deploy the Honey proxy
        honey = Honey(deployProxyWithCreate2(honeyImpl, honeySalt));

        // deploy the HoneyFactory implementation
        address honeyFactoryImpl = deployWithCreate2(0, type(HoneyFactory).creationCode);
        // deploy the HoneyFactory proxy
        honeyFactory = HoneyFactory(deployProxyWithCreate2(honeyFactoryImpl, honeyFactorySalt));

        // initialize the contracts
        honey.initialize(governance, address(honeyFactory));
        honeyFactory.initialize(governance, address(honey), feeReceiver, polFeeCollector);
    }
}
