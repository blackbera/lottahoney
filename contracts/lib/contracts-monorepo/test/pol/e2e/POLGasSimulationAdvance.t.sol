// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./POLGasSim.t.sol";

contract POLGasSimulationAdvance is POLGasSimulationSimple {
    function setUp() public virtual override {
        super.setUp();

        // Create Berachain rewards vaults with consensus asset
        BerachainRewardsVault[] memory vaults = createVaults(3);

        // configure cutting board with three consensus assets
        uint96[] memory weights = new uint96[](3);
        weights[0] = 2500;
        weights[1] = 2500;
        weights[2] = 5000;

        configureWeights(vaults, weights);

        // whitelist and add validator incentives
        addIncentives(vaults, 3);
    }
}
