// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Create2Deployer } from "../base/Create2Deployer.sol";
import { BeraChef } from "./rewards/BeraChef.sol";
import { BerachainRewardsVault } from "./rewards/BerachainRewardsVault.sol";
import { BerachainRewardsVaultFactory } from "./rewards/BerachainRewardsVaultFactory.sol";
import { BlockRewardController } from "./rewards/BlockRewardController.sol";
import { Distributor } from "./rewards/Distributor.sol";

/// @title POLDeployer
/// @author Berachain Team
/// @notice The POLDeployer contract is responsible for deploying the PoL contracts.
contract POLDeployer is Create2Deployer {
    uint8 internal constant maxNumWeightsPerCuttingBoard = 10;

    /// @notice The address of the BeaconDeposit contract.
    /// @dev This is a placeholder address. defined here instead of constructor to avoid stack too deep error.
    address internal constant BEACON_DEPOSIT = 0x4242424242424242424242424242424242424242;

    /// @notice The BeraChef contract.
    // solhint-disable-next-line immutable-vars-naming
    BeraChef public immutable beraChef;

    /// @notice The BlockRewardController contract.
    // solhint-disable-next-line immutable-vars-naming
    BlockRewardController public immutable blockRewardController;

    /// @notice The BerachainRewardsVaultFactory contract.
    // solhint-disable-next-line immutable-vars-naming
    BerachainRewardsVaultFactory public immutable rewardsFactory;

    /// @notice The Distributor contract.
    // solhint-disable-next-line immutable-vars-naming
    Distributor public immutable distributor;

    constructor(
        address bgt,
        address governance,
        address beaconVerifier,
        uint256 beraChefSalt,
        uint256 blockRewardControllerSalt,
        uint256 distributorSalt,
        uint256 rewardsFactorySalt
    ) {
        // deploy the BeraChef implementation
        address beraChefImpl = deployWithCreate2(0, type(BeraChef).creationCode);
        // deploy the BeraChef proxy
        beraChef = BeraChef(deployProxyWithCreate2(beraChefImpl, beraChefSalt));

        // deploy the BlockRewardController implementation
        address blockRewardControllerImpl = deployWithCreate2(0, type(BlockRewardController).creationCode);
        // deploy the BlockRewardController proxy
        blockRewardController =
            BlockRewardController(deployProxyWithCreate2(blockRewardControllerImpl, blockRewardControllerSalt));

        // deploy the Distributor implementation
        address distributorImpl = deployWithCreate2(0, type(Distributor).creationCode);
        // deploy the Distributor proxy
        distributor = Distributor(deployProxyWithCreate2(distributorImpl, distributorSalt));

        // deploy the BerachainRewardsVault implementation
        address vaultImpl = deployWithCreate2(0, type(BerachainRewardsVault).creationCode);
        address rewardsFactoryImpl = deployWithCreate2(0, type(BerachainRewardsVaultFactory).creationCode);
        // deploy the BerachainRewardsVaultFactory proxy
        rewardsFactory = BerachainRewardsVaultFactory(deployProxyWithCreate2(rewardsFactoryImpl, rewardsFactorySalt));

        // initialize the contracts
        beraChef.initialize(
            address(distributor), address(rewardsFactory), governance, BEACON_DEPOSIT, maxNumWeightsPerCuttingBoard
        );
        blockRewardController.initialize(bgt, address(distributor), BEACON_DEPOSIT, governance);
        distributor.initialize(address(beraChef), bgt, address(blockRewardController), governance, beaconVerifier);
        rewardsFactory.initialize(bgt, address(distributor), BEACON_DEPOSIT, governance, vaultImpl);
    }
}
