// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { StdCheats } from "forge-std/StdCheats.sol";
import { SoladyTest } from "solady/test/utils/SoladyTest.sol";
import { LibClone } from "solady/src/utils/LibClone.sol";

import { Honey } from "src/honey/Honey.sol";
import { CollateralVault } from "src/honey/CollateralVault.sol";
import { HoneyFactory, VaultAdmin } from "src/honey/HoneyFactory.sol";
import { MockDAI, MockUSDT, MockDummy } from "@mock/honey/MockAssets.sol";

abstract contract HoneyBaseTest is StdCheats, SoladyTest {
    // Roles
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    HoneyFactory internal factory;
    address internal governance = makeAddr("governance");
    address internal manager = makeAddr("manager");
    address internal feeReceiver = makeAddr("feeReceiver");
    address internal polFeeCollector = makeAddr("polFeeCollector");
    address internal receiver = makeAddr("receiver");
    Honey internal honey;
    CollateralVault daiVault;
    CollateralVault usdtVault;

    MockDAI dai = new MockDAI();
    uint256 daiBalance = 200e18;
    uint256 daiMintRate = 0.99e18;
    uint256 daiRedeemRate = 0.98e18;

    MockUSDT usdt = new MockUSDT();
    uint256 usdtBalance = 100e9;
    uint256 usdtMintRate = 0.99e18;
    uint256 usdtRedeemRate = 0.98e18;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        Honey honeyImpl = new Honey();
        address honeyProxy = LibClone.deployERC1967(address(honeyImpl));
        honey = Honey(honeyProxy);

        factory = HoneyFactory(LibClone.deployERC1967(address(new HoneyFactory())));

        honey.initialize(governance, address(factory));
        factory.initialize(governance, address(honey), feeReceiver, polFeeCollector);

        dai.mint(address(this), daiBalance);
        usdt.mint(address(this), usdtBalance);

        vm.startPrank(governance);
        factory.grantRole(factory.MANAGER_ROLE(), manager);
        daiVault = CollateralVault(address(factory.createVault(address(dai))));
        usdtVault = CollateralVault(address(factory.createVault(address(usdt))));
        vm.stopPrank();

        vm.startPrank(manager);
        factory.setMintRate(address(dai), daiMintRate);
        factory.setRedeemRate(address(dai), daiRedeemRate);
        factory.setMintRate(address(usdt), usdtMintRate);
        factory.setRedeemRate(address(usdt), usdtRedeemRate);
        vm.stopPrank();
    }
}
