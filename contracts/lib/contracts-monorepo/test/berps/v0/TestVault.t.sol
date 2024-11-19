// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { LibClone } from "solady/src/utils/LibClone.sol";

import "@mock/token/MockERC20.sol";
import "@mock/berps/MockFeeCollector.sol";

import "src/berps/core/v0/Vault.sol";
import "src/berps/core/v0/VaultSafetyModule.sol";

contract TestVault is Test {
    MockERC20 public feeAsset;
    Vault public vault;
    VaultSafetyModule public safetyModule;

    address user = makeAddr("user");
    uint256 initialFeeAmt = 6e18;
    uint256 initialDeposit = 12e18;

    function setUp() public {
        feeAsset = new MockERC20();
        feeAsset.initialize("fee", "asset");
        feeAsset.mint(address(this), initialFeeAmt);
        feeAsset.mint(user, 30e18);

        Vault _bHoney = new Vault();
        address bHoneyProxy = LibClone.deployERC1967(address(_bHoney));
        vault = Vault(bHoneyProxy);

        VaultSafetyModule _safetyModule = new VaultSafetyModule();
        address safetyModuleProxy = LibClone.deployERC1967(address(_safetyModule));
        safetyModule = VaultSafetyModule(safetyModuleProxy);
        safetyModule.initialize(
            address(this), address(feeAsset), address(vault), address(new MockFeeCollector(address(feeAsset)))
        );

        IVault.ContractAddresses memory addrs = IVault.ContractAddresses({
            asset: address(feeAsset),
            owner: address(this),
            manager: address(this),
            pnlHandler: address(this),
            safetyModule: address(safetyModule)
        });
        IVault.Params memory params = IVault.Params({
            _maxDailyAccPnlDelta: 1e18,
            _withdrawLockThresholdsPLow: 10_000_000_000_000_000_000,
            _withdrawLockThresholdsPHigh: 20_000_000_000_000_000_000,
            _maxSupplyIncreaseDailyP: 2e18,
            _epochLength: 1 minutes,
            _minRecollatP: 150e18,
            _safeMinSharePrice: 1.1e18
        });
        vault.initialize("fee", "share", addrs, params);

        feeAsset.approve(address(vault), type(uint256).max);
    }

    function makeInitialDeposit() private {
        vm.startPrank(user);
        feeAsset.approve(address(vault), type(uint256).max);
        vault.deposit(initialDeposit, user);
        vm.stopPrank();
    }

    function testBalanceOf() public {
        makeInitialDeposit();

        vault.deposit(3e18, address(this));
        assertEq(vault.balanceOf(address(this)), 3e18);
        assertEq(vault.completeBalanceOf(address(this)), 3e18);
        assertEq(vault.completeBalanceOfAssets(address(this)), 3e18);

        vault.makeWithdrawRequest(1e18);
        assertEq(vault.balanceOf(address(this)), 2e18);
        assertEq(vault.completeBalanceOf(address(this)), 3e18);
        assertEq(vault.completeBalanceOfAssets(address(this)), 3e18);

        assertEq(vault.withdrawRequests(address(this), 1), 0);
        assertEq(vault.withdrawRequests(address(this), 2), 0);
        assertEq(vault.withdrawRequests(address(this), 3), 0);
        assertEq(vault.withdrawRequests(address(this), 4), 1e18);

        // forward to epoch 4
        for (uint256 i = vault.currentEpoch(); i < 4; i++) {
            vm.warp(block.timestamp + i * vault.epochLength() + 1);
            vault.forceNewEpoch();
        }

        vault.withdraw(5e17, address(this), address(this));
        assertEq(vault.balanceOf(address(this)), 2e18);
        assertEq(vault.completeBalanceOf(address(this)), 2.5e18);
        assertEq(vault.completeBalanceOfAssets(address(this)), 2.5e18);

        vault.withdraw(5e17, address(this), address(this));
        assertEq(vault.balanceOf(address(this)), 2e18);
        assertEq(vault.completeBalanceOf(address(this)), 2e18);
        assertEq(vault.completeBalanceOfAssets(address(this)), 2e18);
    }

    function testDistributeReward(uint48 amount) public {
        vm.assume(amount <= initialFeeAmt);
        if (amount % 2 == 1) {
            amount -= 1;
        }

        makeInitialDeposit();

        vault.distributeReward(amount);
        assertEq(vault.totalRewards(), amount);
        assertEq(vault.totalDeposited(), amount + initialDeposit);
    }

    function testAssetsPnL(uint48 amount) public {
        vm.assume(amount <= initialFeeAmt);
        vault.receiveAssets(uint256(amount) * 2, address(this));
        vault.sendAssets(amount, address(this));

        vm.expectRevert(abi.encodeWithSignature("TransferFailed()"));
        vault.sendAssets(uint256(amount) + 1, address(this));
    }
}
