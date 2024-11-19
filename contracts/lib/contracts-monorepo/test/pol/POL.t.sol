// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { BeraChef, IBeraChef } from "src/pol/rewards/BeraChef.sol";
import { BGT } from "src/pol/BGT.sol";
import { BGTStaker } from "src/pol/BGTStaker.sol";
import { BerachainRewardsVaultFactory } from "src/pol/rewards/BerachainRewardsVaultFactory.sol";
import { BlockRewardController } from "src/pol/rewards/BlockRewardController.sol";
import { Distributor } from "src/pol/rewards/Distributor.sol";
import { FeeCollector } from "src/pol/FeeCollector.sol";
import { BGTFeeDeployer } from "src/pol/BGTFeeDeployer.sol";
import { POLDeployer } from "src/pol/POLDeployer.sol";
import { WBERA } from "src/WBERA.sol";
import { BeaconDepositMock } from "test/mock/pol/BeaconDepositMock.sol";
import { MockBeaconVerifier } from "test/mock/pol/MockBeaconVerifier.sol";

abstract contract POLTest is Test {
    uint256 internal constant PAYOUT_AMOUNT = 1e18;
    uint256 internal constant HISTORY_BUFFER_LENGTH = 8191;
    address internal governance = makeAddr("governance");
    // beacon deposit address defined in the contract.
    address internal beaconDepositContract = 0x4242424242424242424242424242424242424242;
    address internal operator = makeAddr("operator");
    bytes internal valPubkey = "validator pubkey";
    BeraChef internal beraChef;
    BGT internal bgt;
    BGTStaker internal bgtStaker;
    BlockRewardController internal blockRewardController;
    BerachainRewardsVaultFactory internal factory;
    FeeCollector internal feeCollector;
    Distributor internal distributor;
    POLDeployer internal polDeployer;
    BGTFeeDeployer internal feeDeployer;
    WBERA internal wbera;
    address beaconVerifier;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        deployPOL(governance);

        wbera = new WBERA();
        deployBGTFees(governance);

        vm.startPrank(governance);
        bgt.setMinter(address(blockRewardController));
        bgt.setBeaconDepositContract(beaconDepositContract);
        bgt.setStaker(address(bgtStaker));
        bgt.whitelistSender(address(distributor), true);
        // add native token to BGT for backing
        vm.deal(address(bgt), 100_000 ether);
        vm.stopPrank();
    }

    function deployBGT(address owner) internal {
        bgt = new BGT();
        bgt.initialize(owner);
    }

    function deployBGTFees(address owner) internal {
        feeDeployer = new BGTFeeDeployer(address(bgt), owner, address(wbera), 0, 0, PAYOUT_AMOUNT);
        bgtStaker = feeDeployer.bgtStaker();
        feeCollector = feeDeployer.feeCollector();
    }

    function deployPOL(address owner) internal {
        deployBGT(owner);

        // deploy the beacon deposit contract at the address defined in the contract.
        deployCodeTo("BeaconDepositMock.sol", beaconDepositContract);
        // set the operator of the validator.
        BeaconDepositMock(beaconDepositContract).setOperator(valPubkey, operator);
        // deploy beacon verifier mock
        beaconVerifier = address(new MockBeaconVerifier());

        polDeployer = new POLDeployer(address(bgt), owner, beaconVerifier, 0, 0, 0, 0);
        beraChef = polDeployer.beraChef();
        blockRewardController = polDeployer.blockRewardController();
        factory = polDeployer.rewardsFactory();
        distributor = polDeployer.distributor();
    }
}
