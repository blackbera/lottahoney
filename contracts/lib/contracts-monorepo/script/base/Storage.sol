// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Honey } from "src/honey/Honey.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { BeraChef, IBeraChef } from "src/pol/rewards/BeraChef.sol";
import { BGT } from "src/pol/BGT.sol";
import { BGTStaker } from "src/pol/BGTStaker.sol";
import { BerachainRewardsVault } from "src/pol/rewards/BerachainRewardsVault.sol";
import { BerachainRewardsVaultFactory } from "src/pol/rewards/BerachainRewardsVaultFactory.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";
import { FeeCollector } from "src/pol/FeeCollector.sol";
import { BGTFeeDeployer } from "src/pol/BGTFeeDeployer.sol";
import { POLDeployer } from "src/pol/POLDeployer.sol";
import { WBERA } from "src/WBERA.sol";

abstract contract Storage {
    // The address of BGT will be hardcoded.
    BGT internal bgt = BGT(0xbDa130737BDd9618301681329bF2e46A016ff9Ad);

    BeraChef internal beraChef;
    BGTStaker internal bgtStaker;
    BlockRewardController internal blockRewardController;
    BerachainRewardsVaultFactory internal rewardsFactory;
    BerachainRewardsVault internal rewardsVault;
    FeeCollector internal feeCollector;
    Distributor internal distributor;
    POLDeployer internal polDeployer;
    BGTFeeDeployer internal feeDeployer;
    WBERA internal wbera;
    address internal timelock;
    Honey internal honey;
    HoneyFactory internal honeyFactory;
}
