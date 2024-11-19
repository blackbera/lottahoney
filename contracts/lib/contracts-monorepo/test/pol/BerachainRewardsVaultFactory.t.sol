// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";
import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { MockRewardsVault } from "test/mock/pol/MockRewardsVault.sol";
import { BerachainRewardsVault } from "src/pol/rewards/BerachainRewardsVault.sol";
import { BerachainRewardsVaultFactory } from "src/pol/rewards/BerachainRewardsVaultFactory.sol";
import { IPOLErrors } from "src/pol/interfaces/IBerachainRewardsVaultFactory.sol";
import { MockHoney } from "@mock/honey/MockHoney.sol";
import { POLTest } from "./POL.t.sol";

contract BerachainRewardsVaultFactoryTest is POLTest {
    MockHoney internal honey;

    function setUp() public override {
        super.setUp();
        honey = new MockHoney();
    }

    function test_InitialState() public view {
        assertEq(factory.bgt(), address(bgt));
        assertEq(factory.distributor(), address(distributor));
        assertEq(factory.getVault(address(honey)), address(0));
        assert(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), governance));
    }

    function testFuzz_CreateRewardsVault(address deployer) public {
        vm.prank(deployer);
        address vault = factory.createRewardsVault(address(honey));
        assertEq(factory.predictRewardsVaultAddress(address(honey)), vault);
        assertEq(factory.getVault(address(honey)), vault);
    }

    function test_CreateRewardsVault_FailIfAlreadyCreated() public {
        test_CreateRewardsVault();
        vm.expectRevert(IPOLErrors.VaultAlreadyExists.selector);
        factory.createRewardsVault(address(honey));
    }

    function test_CreateRewardsVault() public returns (address vault) {
        vault = factory.createRewardsVault(address(honey));
        assertEq(factory.predictRewardsVaultAddress(address(honey)), vault);
        assertEq(factory.getVault(address(honey)), vault);
    }

    function test_GetVaultsLength() public {
        assertEq(factory.allVaultsLength(), 0);
        test_CreateRewardsVault();
        // creates 1 vault
        assertEq(factory.allVaultsLength(), 1);
    }

    function test_TransferOwnershipOfBeaconFailsIfNotOwner() public {
        address newAddress = makeAddr("newAddress");
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        vm.expectRevert(UpgradeableBeacon.Unauthorized.selector);
        beacon.transferOwnership(newAddress);
    }

    function test_TransferOwnershipOfBeaconFailsIfZeroAddress() public {
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        vm.expectRevert(UpgradeableBeacon.NewOwnerIsZeroAddress.selector);
        vm.prank(governance);
        beacon.transferOwnership(address(0));
    }

    function test_TransferOwnershipOfBeacon() public {
        address newAddress = makeAddr("newAddress");
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        vm.prank(governance);
        beacon.transferOwnership(newAddress);
        assertEq(beacon.owner(), newAddress);
    }

    function test_UpgradeBeaconProxyImplFailsIfNotOwner() public {
        address newImplementation = address(new MockRewardsVault());
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        // implementation update of the beacon fails as caller is not the owner.
        vm.expectRevert(UpgradeableBeacon.Unauthorized.selector);
        beacon.upgradeTo(newImplementation);
    }

    function test_UpgradeBeaconProxy() public returns (address vault, address beacon) {
        // deploy a rewardsVault beaconProxy with an old implementation
        vault = test_CreateRewardsVault();
        address newImplementation = address(new MockRewardsVault());
        // update the implementation of the beacon
        beacon = factory.beacon();
        vm.prank(governance);
        // update the implementation of the beacon
        UpgradeableBeacon(beacon).upgradeTo(newImplementation);
        // check the new implementation of the beacon
        assertEq(MockRewardsVault(vault).VERSION(), 2);
        assertEq(MockRewardsVault(vault).isNewImplementation(), true);
    }

    function test_UpgradeAndDowngradeOfBeaconProxy() public {
        (address vault, address beacon) = test_UpgradeBeaconProxy();
        // downgrade the implementation of the beacon
        address oldImplementation = address(new BerachainRewardsVault());
        vm.prank(governance);
        UpgradeableBeacon(beacon).upgradeTo(oldImplementation);
        // Call will revert as old implementation does not have isNewImplementation function.
        vm.expectRevert();
        MockRewardsVault(vault).isNewImplementation();
    }

    function test_UpgradeToFailsIfNotOwner() public {
        testFuzz_UpgradeToFailsIfNotOwner(address(this));
    }

    function testFuzz_UpgradeToFailsIfNotOwner(address caller) public {
        vm.assume(caller != governance);
        address newImplementation = address(new BerachainRewardsVaultFactory());
        bytes32 role = factory.DEFAULT_ADMIN_ROLE();
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, role));
        factory.upgradeToAndCall(newImplementation, bytes(""));
    }

    function test_UpgradeToFailsIfImplIsNotUUPS() public {
        vm.prank(governance);
        // call will revert as new implementation is not UUPS.
        vm.expectRevert();
        factory.upgradeToAndCall(address(this), bytes(""));
    }

    function test_UpgradeToAndCall() public {
        address newImplementation = address(new BerachainRewardsVaultFactory());
        vm.prank(governance);
        vm.expectEmit();
        emit ERC1967Utils.Upgraded(newImplementation);
        factory.upgradeToAndCall(newImplementation, bytes(""));
        bytes32 slot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        address _implementation = address(uint160(uint256(vm.load(address(factory), slot))));
        assertEq(_implementation, newImplementation);
    }
}
