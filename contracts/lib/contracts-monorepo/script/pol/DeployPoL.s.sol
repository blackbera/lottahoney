// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { console2 } from "forge-std/Script.sol";

import { TransferBeraToBgt } from "./TransferBeraToBgt.s.sol";
import { AddIncentive } from "./AddIncentive.s.sol";
import { DeployRewardsVault } from "./DeployRewardsVault.s.sol";
import { Create2Deployer } from "src/base/Create2Deployer.sol";
import "../base/Storage.sol";

contract DeployPoL is Create2Deployer, Storage, TransferBeraToBgt, AddIncentive, DeployRewardsVault {
    address internal constant BEACON_VERIFIER = 0x10B1dEbfE066e79E26f21B0212e9693658Fdb12d;
    address internal constant BEACON_DEPOSIT = 0x4242424242424242424242424242424242424242;
    uint256 internal constant WBERA_SALT = 1;
    uint256 internal constant BERA_CHEF_SALT = 1;
    uint256 internal constant BLOCK_REWARD_CONTROLLER_SALT = 1;
    uint256 internal constant DISTRIBUTOR_SALT = 1;
    uint256 internal constant REWARDS_FACTORY_SALT = 1;
    uint256 internal constant BGT_STAKER_SALT = 1;
    uint256 internal constant FEE_COLLECTOR_SALT = 1;
    uint256 internal constant REWARD_RATE = 1500 ether;
    uint256 internal constant BASE_RATE = 1 ether;
    uint256 internal constant MIN_BOOSTED_REWARD_RATE = 0 ether;
    uint256 internal constant BOOST_MULTIPLIER = 3 ether;
    int256 internal constant REWARD_CONVEXITY = 0.5 ether;
    uint256 internal constant PAYOUT_AMOUNT = 100 ether;
    uint256 internal constant RESERVE_BERA_AMOUNT = 5e8 ether;
    uint256 internal constant INITIAL_BGT_AMOUNT = 1e10 ether;
    uint64 internal constant HISTORY_BUFFER_LENGTH = 8191;

    function run() public override(TransferBeraToBgt, AddIncentive, DeployRewardsVault) {
        vm.startBroadcast();

        console2.log("Sender address: ", msg.sender);

        wbera = WBERA(payable(deployWithCreate2(WBERA_SALT, type(WBERA).creationCode)));
        console2.log("WBERA deployed at:", address(wbera));

        deployPoL();

        deployBGTFees();

        configPoL();

        vm.stopBroadcast();
    }

    function deployBGTFees() internal {
        console2.log("Deploying BGTFeeDeployer...");
        feeDeployer = new BGTFeeDeployer(
            address(bgt), msg.sender, address(wbera), BGT_STAKER_SALT, FEE_COLLECTOR_SALT, PAYOUT_AMOUNT
        );
        console2.log("BGTFeeDeployer deployed at:", address(feeDeployer));
        bgtStaker = feeDeployer.bgtStaker();
        console2.log("BGTStaker deployed at:", address(bgtStaker));
        feeCollector = feeDeployer.feeCollector();
        console2.log("FeeCollector deployed at:", address(feeCollector));

        require(feeCollector.payoutAmount() == PAYOUT_AMOUNT, "Fee collector payout amount is not set");
        console2.log("Set the payout amount to %d", PAYOUT_AMOUNT);
    }

    function deployPoL() internal {
        console2.log("Deploying PoL contracts...");
        // deploy the BGT contract
        bgt = new BGT();
        console2.log("BGT deployed at:", address(bgt));
        bgt.initialize(msg.sender);
        require(
            keccak256(bytes(bgt.CLOCK_MODE())) == keccak256("mode=blocknumber&from=default"),
            "BGT CLOCK_MODE is incorrect"
        );

        console2.log("POLDeployer init code size", type(POLDeployer).creationCode.length);
        polDeployer = new POLDeployer(
            address(bgt),
            msg.sender,
            BEACON_VERIFIER,
            BERA_CHEF_SALT,
            BLOCK_REWARD_CONTROLLER_SALT,
            DISTRIBUTOR_SALT,
            REWARDS_FACTORY_SALT
        );
        console2.log("POLDeployer deployed at:", address(polDeployer));

        beraChef = polDeployer.beraChef();
        console2.log("BeraChef deployed at:", address(beraChef));

        blockRewardController = polDeployer.blockRewardController();
        console2.log("BlockRewardController deployed at:", address(blockRewardController));

        distributor = polDeployer.distributor();
        console2.log("Distributor deployed at:", address(distributor));

        require(address(distributor.beaconVerifier()) == BEACON_VERIFIER, "Distributor Beacon Verifier is not set");
        console2.log("Set the beacon verifier to %s", BEACON_VERIFIER);

        rewardsFactory = polDeployer.rewardsFactory();
        console2.log("RewardsFactory deployed at:", address(rewardsFactory));
    }

    function configPoL() internal {
        // Config BlockRewardController
        // Set the base rate.
        blockRewardController.setBaseRate(BASE_RATE);
        console2.log("Set the base rate to be %d BGT per block", BASE_RATE);
        // Set the reward rate.
        blockRewardController.setRewardRate(REWARD_RATE);
        console2.log("Set the reward rate to be %d BGT per block", REWARD_RATE);
        // Set the min boosted reward rate.
        blockRewardController.setMinBoostedRewardRate(MIN_BOOSTED_REWARD_RATE);
        console2.log("Set the min boosted reward rate to be %d BGT per block", MIN_BOOSTED_REWARD_RATE);
        // Set the boost multiplier parameter.
        blockRewardController.setBoostMultiplier(BOOST_MULTIPLIER);
        console2.log("Set the boost multiplier param to be %d", BOOST_MULTIPLIER);
        // Set the reward convexity parameter.
        blockRewardController.setRewardConvexity(REWARD_CONVEXITY);
        console2.log("Set the reward convexity param to be %d", REWARD_CONVEXITY);

        // Config BeraChef
        // Set the cutting board delay
        beraChef.setCuttingBoardBlockDelay(HISTORY_BUFFER_LENGTH);
        console2.log("Set the cutting board delay to be %d blocks", HISTORY_BUFFER_LENGTH);
        // Setup the cutting board and vault for HONEY
        rewardsVault = deployRewardsVault(address(honey));
        configRewardsVault(address(rewardsVault));

        // config BGT
        bgt.setBeaconDepositContract(BEACON_DEPOSIT);
        bgt.setStaker(address(bgtStaker));
        bgt.whitelistSender(address(distributor), true);
        bgt.whitelistSender(msg.sender, true);

        // mint 1000 BGT to the sender
        bgt.setMinter(msg.sender);

        forceSafeTransferBERA(address(bgt), RESERVE_BERA_AMOUNT + INITIAL_BGT_AMOUNT);
        console2.log("Transferred %d BERA to BGT", RESERVE_BERA_AMOUNT + INITIAL_BGT_AMOUNT);

        bgt.mint(msg.sender, INITIAL_BGT_AMOUNT);
        console2.log("Minted %d BGT to %s", INITIAL_BGT_AMOUNT, msg.sender);
        // set the minter to the block reward controller
        bgt.setMinter(address(blockRewardController));
    }
}
