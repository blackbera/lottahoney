// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { BerpsDeployer } from "../../src/berps/deploy/v0/BerpsDeployer.sol";

/// @dev Update the DEPLOYER with the address of the BerpsDeployer.
library Addresses {
    BerpsDeployer public constant DEPLOYER = BerpsDeployer(address(0));
}
