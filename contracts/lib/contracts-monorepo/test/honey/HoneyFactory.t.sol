// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { LibClone } from "solady/src/utils/LibClone.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { ERC4626 } from "solady/src/tokens/ERC4626.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { UpgradeableBeacon } from "solady/src/utils/UpgradeableBeacon.sol";

import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { CollateralVault } from "src/honey/CollateralVault.sol";
import { HoneyBaseTest, VaultAdmin } from "./HoneyBase.t.sol";
import { IHoneyErrors } from "src/honey/IHoneyErrors.sol";
import { IHoneyFactory } from "src/honey/IHoneyFactory.sol";
import { MockVault, FaultyVault } from "@mock/honey/MockVault.sol";
import { MockDAI, MockUSDT, MockDummy } from "@mock/honey/MockAssets.sol";

contract HoneyFactoryTest is HoneyBaseTest {
    CollateralVault dummyVault;

    MockDummy dummy = new MockDummy();
    uint256 dummyBalance = 100e20; // 100 Dummy
    uint256 dummyMintRate = 0.99e18;
    uint256 dummyRedeemRate = 0.98e18;

    function setUp() public override {
        super.setUp();

        dummy.mint(address(this), dummyBalance);
        vm.prank(governance);
        dummyVault = CollateralVault(address(factory.createVault(address(dummy))));
        vm.startPrank(manager);
        factory.setMintRate(address(dummy), dummyMintRate);
        factory.setRedeemRate(address(dummy), dummyRedeemRate);
        vm.stopPrank();
    }

    function test_Initialize_ParamsSet() public {
        assertEq(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), governance), true);
        assertEq(address(factory.honey()), address(honey));
        assertEq(factory.feeReceiver(), feeReceiver);
        assertEq(factory.polFeeCollector(), polFeeCollector);
        assertEq(factory.polFeeCollectorFeeRate(), 5e17);
    }

    function test_CreateVault() public {
        uint256 initialVaultsLength = factory.numRegisteredAssets();
        address dummyAsset = address(new MockDummy());
        address predictedVault = factory.predictVaultAddress(dummyAsset);
        vm.prank(governance);
        vm.expectEmit();
        emit VaultAdmin.VaultCreated(predictedVault, dummyAsset);
        address vault = (address(factory.createVault(dummyAsset)));
        assertEq(vault, predictedVault);
        // registeredAssets and vaults mappings are updated
        assertEq(address(factory.vaults(dummyAsset)), vault);
        assertEq(factory.numRegisteredAssets(), initialVaultsLength + 1);
    }

    function test_createAlreadyRegisteredVault() external {
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.VaultAlreadyRegistered.selector, address(dai)));
        factory.createVault(address(dai));
    }

    function testFuzz_setMintRate(uint256 _mintRate) external {
        _mintRate = _bound(_mintRate, 98e16, 1e18);
        vm.prank(manager);
        vm.expectEmit();
        emit IHoneyFactory.MintRateSet(address(dai), _mintRate);
        factory.setMintRate(address(dai), _mintRate);
        assertEq(factory.getMintRate(address(dai)), _mintRate);
    }

    function testFuzz_setRedeemRate(uint256 _redeemRate) external {
        _redeemRate = _bound(_redeemRate, 98e16, 1e18);
        vm.prank(manager);
        vm.expectEmit();
        emit IHoneyFactory.RedeemRateSet(address(dai), _redeemRate);
        factory.setRedeemRate(address(dai), _redeemRate);
        assertEq(factory.getRedeemRate(address(dai)), _redeemRate);
    }

    function test_setMintRate_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.setMintRate(address(dai), 1e18);
    }

    function test_setRedeemRate_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.setRedeemRate(address(dai), 1e18);
    }

    function testFuzz_setMintRate_failsWithOverOneHundredPercentRate(uint256 _mintRate) external {
        _mintRate = _bound(_mintRate, 1e18 + 1, type(uint256).max);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.OverOneHundredPercentRate.selector, _mintRate));
        factory.setMintRate(address(dai), _mintRate);
    }

    function testFuzz_setRedeemRate_failsWithOverOneHundredPercentRate(uint256 _redeemRate) external {
        _redeemRate = _bound(_redeemRate, 1e18 + 1, type(uint256).max);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.OverOneHundredPercentRate.selector, _redeemRate));
        factory.setRedeemRate(address(dai), _redeemRate);
    }

    function testFuzz_setMintRate_failsWithUnderNinetyEightPercentRate(uint256 _mintRate) external {
        _mintRate = _bound(_mintRate, 0, 98e16 - 1);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.UnderNinetyEightPercentRate.selector, _mintRate));
        factory.setMintRate(address(dai), _mintRate);
    }

    function testFuzz_setRedeemRate_failsWithUnderNinetyEightPercentRate(uint256 _redeemRate) external {
        _redeemRate = _bound(_redeemRate, 0, 98e16 - 1);
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.UnderNinetyEightPercentRate.selector, _redeemRate));
        factory.setRedeemRate(address(dai), _redeemRate);
    }

    function test_setPOLFeeCollectorFeeRate_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.setPOLFeeCollectorFeeRate(1e18);
    }

    function test_setPOLFeeCollectorFeeRate_failsWithOverOneHundredPercentRate(uint256 _polFeeCollectorFeeRate)
        external
    {
        _polFeeCollectorFeeRate = _bound(_polFeeCollectorFeeRate, 1e18 + 1, type(uint256).max);
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IHoneyErrors.OverOneHundredPercentRate.selector, _polFeeCollectorFeeRate)
        );
        factory.setPOLFeeCollectorFeeRate(_polFeeCollectorFeeRate);
    }

    function test_setPOLFeeCollectorFeeRate() external {
        uint256 polFeeCollectorFeeRate = 1e16; // 1%
        testFuzz_setPOLFeeCollectorFeeRate(polFeeCollectorFeeRate);
    }

    function testFuzz_setPOLFeeCollectorFeeRate(uint256 _polFeeCollectorFeeRate) public {
        _polFeeCollectorFeeRate = _bound(_polFeeCollectorFeeRate, 0, 1e18);
        vm.expectEmit();
        emit IHoneyFactory.POLFeeCollectorFeeRateSet(_polFeeCollectorFeeRate);
        vm.prank(manager);
        factory.setPOLFeeCollectorFeeRate(_polFeeCollectorFeeRate);
        assertEq(factory.polFeeCollectorFeeRate(), _polFeeCollectorFeeRate);
    }

    function testFuzz_mint_failsWithUnregisteredAsset(uint32 _usdtToMint) external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        vm.prank(governance);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factory.mint(address(usdtNew), _usdtToMint, receiver);
    }

    function test_mint_failsWithBadCollateralAsset() external {
        // sets dai as bad collateral asset.
        test_setCollateralAssetStatus();
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetIsBadCollateral.selector, address(dai)));
        factory.mint(address(dai), 100e18, receiver);
    }

    function testFuzz_mint_failWithPausedFactory(uint128 _daiToMint) external {
        vm.prank(manager);
        factory.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        factory.mint(address(dai), _daiToMint, receiver);
    }

    function testFuzz_mint_failsWithInsufficientAllowance(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 1, daiBalance);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        factory.mint(address(dai), _daiToMint, receiver);
    }

    function testFuzz_mint(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 0, daiBalance);
        uint256 mintedHoneys = _initialMint(_daiToMint);
        _verifyOutputOfMint(dai, daiVault, daiBalance, _daiToMint, mintedHoneys);
    }

    function testFuzz_mintWithLowerDecimalAsset(uint256 _usdtToMint) public returns (uint256 mintedHoneys) {
        _usdtToMint = _bound(_usdtToMint, 0, usdtBalance);
        uint256 honeyOverUsdtRate = 1e12;
        mintedHoneys = ((_usdtToMint * honeyOverUsdtRate) * usdtMintRate) / 1e18;
        usdt.approve(address(factory), _usdtToMint);
        factory.mint(address(usdt), _usdtToMint, receiver);
        _verifyOutputOfMint(usdt, usdtVault, usdtBalance, _usdtToMint, mintedHoneys);
    }

    function testFuzz_mintWithHigherDecimalAsset(uint256 _dummyToMint) external {
        _dummyToMint = _bound(_dummyToMint, 0, dummyBalance);
        uint256 dummyOverHoneyRate = 1e2;
        uint256 mintedHoneys = (((_dummyToMint / dummyOverHoneyRate)) * dummyMintRate) / 1e18;
        dummy.approve(address(factory), _dummyToMint);
        factory.mint(address(dummy), _dummyToMint, receiver);
        _verifyOutputOfMint(dummy, dummyVault, dummyBalance, _dummyToMint, mintedHoneys);
    }

    function test_mint() external {
        uint256 daiToMint = 100e18;
        uint256 mintedHoneys = (daiToMint * daiMintRate) / 1e18;
        dai.approve(address(factory), daiToMint);
        vm.expectEmit();
        emit IHoneyFactory.HoneyMinted(address(this), receiver, address(dai), daiToMint, mintedHoneys);
        factory.mint(address(dai), daiToMint, receiver);
    }

    function testFuzz_redeem_failsWithUnregisteredAsset(uint128 _honeyAmount) external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factory.redeem(address(usdtNew), _honeyAmount, receiver);
    }

    function testFuzz_redeem_failWithPausedFactory(uint128 _honeyAmount) external {
        vm.prank(manager);
        factory.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        factory.redeem(address(dai), _honeyAmount, receiver);
    }

    function testFuzz_redeem_failsWithInsufficientHoneys(uint256 _honeyAmount) external {
        _honeyAmount = _bound(_honeyAmount, 1, type(uint256).max);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        factory.redeem(address(dai), _honeyAmount, receiver);
    }

    function testFuzz_redeem_failsWithInsufficientShares(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 100, daiBalance);
        uint256 mintedHoneys = _initialMintToAParticularReceiver(_daiToMint, address(this));
        vm.prank(address(factory));
        // vaultAdmin mints honey to this address without increasing shares
        honey.mint(address(this), mintedHoneys);
        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);
        factory.redeem(address(dai), (mintedHoneys * 3) / 2, address(this));
    }

    function testFuzz_redeem(uint256 _honeyToRedeem) external {
        uint256 daiToMint = 100e18;
        uint256 mintedHoneys = _initialMint(daiToMint);
        _honeyToRedeem = _bound(_honeyToRedeem, 0, mintedHoneys);
        uint256 redeemedDai = (_honeyToRedeem * daiRedeemRate) / 1e18;
        assertEq(factory.previewRedeem(address(dai), _honeyToRedeem), redeemedDai);
        vm.prank(receiver);
        factory.redeem(address(dai), _honeyToRedeem, address(this));
        // minted shares and daiToMint are equal as both have same decimals i.e 1e18
        _verifyOutputOfRedeem(dai, daiVault, daiBalance, daiToMint, daiToMint, redeemedDai, _honeyToRedeem);
    }

    function testFuzz_redeemWithLowerDecimalAsset(uint256 _honeyToRedeem) external {
        uint256 usdtToMint = 10e6; // 10 UST
        uint256 honeyOverUsdtRate = 1e12;
        uint256 mintedShares = usdtToMint * honeyOverUsdtRate;
        // upper limit is equal to minted honeys
        _honeyToRedeem = _bound(_honeyToRedeem, 0, (mintedShares * usdtMintRate) / 1e18);
        uint256 redeemedUsdt = (_honeyToRedeem * usdtRedeemRate) / 1e18 / honeyOverUsdtRate;
        usdt.approve(address(factory), usdtToMint);
        factory.mint(address(usdt), usdtToMint, receiver);
        assertEq(factory.previewRedeem(address(usdt), _honeyToRedeem), redeemedUsdt);
        vm.prank(receiver);
        factory.redeem(address(usdt), _honeyToRedeem, address(this));
        _verifyOutputOfRedeem(usdt, usdtVault, usdtBalance, usdtToMint, mintedShares, redeemedUsdt, _honeyToRedeem);
    }

    function testFuzz_redeemWithHigherDecimalAsset(uint256 _honeyToRedeem) external {
        uint256 dummyToMint = 10e20; // 10 dummy
        // 1e20 wei DUMMY ~ 1e18 wei Honey -> 0.9e18 wei Honey
        uint256 dummyOverHoneyRate = 1e2;
        uint256 mintedShares = dummyToMint / dummyOverHoneyRate;
        // upper limit is equal to minted honeys
        _honeyToRedeem = _bound(_honeyToRedeem, 0, (mintedShares * dummyMintRate) / 1e18);
        uint256 redeemedDummy = ((_honeyToRedeem * usdtRedeemRate) / 1e18) * dummyOverHoneyRate;
        dummy.approve(address(factory), dummyToMint);
        factory.mint(address(dummy), dummyToMint, receiver);
        assertEq(factory.previewRedeem(address(dummy), _honeyToRedeem), redeemedDummy);
        vm.prank(receiver);
        factory.redeem(address(dummy), _honeyToRedeem, address(this));
        _verifyOutputOfRedeem(
            dummy, dummyVault, dummyBalance, dummyToMint, mintedShares, redeemedDummy, _honeyToRedeem
        );
    }

    function test_redeem() external {
        uint256 daiToMint = 100e18;
        uint256 mintedHoneys = _initialMint(daiToMint);
        uint256 redeemedDai = (mintedHoneys * daiRedeemRate) / 1e18;
        vm.expectEmit();
        emit IHoneyFactory.HoneyRedeemed(receiver, address(this), address(dai), redeemedDai, mintedHoneys);
        vm.prank(receiver);
        factory.redeem(address(dai), mintedHoneys, address(this));
    }

    function test_setFeeReceiver_failsWithoutAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), DEFAULT_ADMIN_ROLE
            )
        );
        factory.setFeeReceiver(receiver);
    }

    function test_setFeeReceiver_failsWithZeroAddress() external {
        vm.prank(governance);
        vm.expectRevert(IHoneyErrors.ZeroAddress.selector);
        factory.setFeeReceiver(address(0));
    }

    function test_setFeeReceiver() external {
        address newReceiver = makeAddr("newReceiver");
        testFuzz_setFeeReceiver(newReceiver);
    }

    function testFuzz_setFeeReceiver(address _receiver) public {
        vm.assume(_receiver != address(0));
        vm.expectEmit();
        emit VaultAdmin.FeeReceiverSet(_receiver);
        vm.prank(governance);
        factory.setFeeReceiver(_receiver);
        assertEq(factory.feeReceiver(), _receiver);
    }

    function test_setPOLFeeCollector_failsWithoutAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), DEFAULT_ADMIN_ROLE
            )
        );
        factory.setPOLFeeCollector(polFeeCollector);
    }

    function test_setPOLFeeCollector_failsWithZeroAddress() external {
        vm.prank(governance);
        vm.expectRevert(IHoneyErrors.ZeroAddress.selector);
        factory.setPOLFeeCollector(address(0));
    }

    function test_setPOLFeeCollector() external {
        address newPOLFeeCollector = makeAddr("newPOLFeeCollector");
        testFuzz_setPOLFeeCollector(newPOLFeeCollector);
    }

    function testFuzz_setPOLFeeCollector(address _polFeeCollector) public {
        vm.assume(_polFeeCollector != address(0));
        vm.expectEmit();
        emit VaultAdmin.POLFeeCollectorSet(_polFeeCollector);
        vm.prank(governance);
        factory.setPOLFeeCollector(_polFeeCollector);
        assertEq(factory.polFeeCollector(), _polFeeCollector);
    }

    function test_setCollateralAssetStatus_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.setCollateralAssetStatus(address(dai), true);
    }

    function test_setCollateralAssetStatus_failsWithUnregisteredAsset() external {
        MockUSDT usdtNew = new MockUSDT(); // new unregistered usdt token instance
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, address(usdtNew)));
        factory.setCollateralAssetStatus(address(usdtNew), true);
    }

    function test_setCollateralAssetStatus_failsWithSameState() external {
        vm.prank(manager);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssestAlreadyInSameState.selector, address(dai)));
        factory.setCollateralAssetStatus(address(dai), false);
    }

    function test_setCollateralAssetStatus() public {
        vm.prank(manager);
        vm.expectEmit();
        emit VaultAdmin.CollateralAssetStatusSet(address(dai), true);
        factory.setCollateralAssetStatus(address(dai), true);
        assertEq(factory.isBadCollateralAsset(address(dai)), true);
    }

    function testFuzz_withdrawFee_failsWithAssetNotRegistered() external {
        address usdtNew = address(new MockUSDT()); // new unregistered usdt token instance
        vm.prank(feeReceiver);
        vm.expectRevert(abi.encodeWithSelector(IHoneyErrors.AssetNotRegistered.selector, usdtNew));
        factory.withdrawFee(usdtNew, feeReceiver);
    }

    function test_withdrawFee_WithZeroCollectedFee() external {
        // Should not revert
        assertEq(factory.collectedFees(feeReceiver, address(dai)), 0);
        factory.withdrawFee(address(dai), feeReceiver);
        assertEq(dai.balanceOf(feeReceiver), 0);
    }

    function test_WithdrawFee_TestEvent() external {
        uint256 usdtToMint = 100e6; // 100 USDT
        uint256 mintedHoneys = testFuzz_mintWithLowerDecimalAsset(usdtToMint);
        uint256 usdtVaultTotalFeeShares = usdtToMint * 10 ** 12 - mintedHoneys;
        uint256 polFeeCollectorFeeShares = usdtVaultTotalFeeShares / 2;
        uint256 polFeeCollectorRedeemAssests = polFeeCollectorFeeShares / 10 ** 12;
        assertEq(factory.collectedFees(polFeeCollector, address(usdt)), polFeeCollectorFeeShares);
        vm.expectEmit();
        emit VaultAdmin.CollectedFeeWithdrawn(
            address(usdt), polFeeCollector, polFeeCollectorFeeShares, polFeeCollectorRedeemAssests
        );
        factory.withdrawFee(address(usdt), polFeeCollector);
        assertEq(usdt.balanceOf(polFeeCollector), polFeeCollectorRedeemAssests);
    }

    function testFuzz_withdrawFee(uint256 _daiToMint) public {
        _daiToMint = _bound(_daiToMint, 0, daiBalance);
        uint256 mintedHoneys = _initialMint(_daiToMint);
        uint256 daiTotalFee = _daiToMint - mintedHoneys;
        uint256 feeReceiverFee = daiTotalFee - daiTotalFee / 2;
        assertEq(dai.balanceOf(feeReceiver), 0);
        // This will withdraw all dai fee for feeReceiver
        factory.withdrawFee(address(dai), feeReceiver);
        assertEq(dai.balanceOf(feeReceiver), feeReceiverFee);
        // fee receiver should not have any shares in the daiVault
        assertEq(daiVault.balanceOf(feeReceiver), 0);
        // fee receiver should have the USDC equal to daiFeeToWithdraw in his balance
        assertEq(factory.collectedFees(feeReceiver, address(dai)), 0);
    }

    function test_CollectedFees() external {
        testFuzz_CollectedFeesWithDifferentFeeRate(98e16, 100e18);
    }

    function testFuzz_CollectedFeesWithDifferentFeeRate(uint256 _polFeeCollectorFeeRate, uint256 daiToMint) public {
        _polFeeCollectorFeeRate = _bound(_polFeeCollectorFeeRate, 0, 1e18);
        daiToMint = _bound(daiToMint, 0, daiBalance);
        testFuzz_setPOLFeeCollectorFeeRate(_polFeeCollectorFeeRate);
        uint256 mintedHoneys = _initialMint(daiToMint);
        uint256 daiTotalFee = daiToMint - mintedHoneys;
        uint256 polFeeCollectorFee = (daiTotalFee * _polFeeCollectorFeeRate) / 1e18;
        uint256 feeReceiverFee = daiTotalFee - polFeeCollectorFee;
        assertEq(factory.collectedFees(feeReceiver, address(dai)), feeReceiverFee);
        assertEq(factory.collectedFees(polFeeCollector, address(dai)), polFeeCollectorFee);
    }

    function testFuzz_withdrawAllFee(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 0, daiBalance);
        uint256 mintedHoneys = _initialMint(_daiToMint);
        uint256 daiTotalFee = _daiToMint - mintedHoneys;
        uint256 polFeeCollectorFee = daiTotalFee / 2;
        uint256 feeReceiverFee = daiTotalFee - polFeeCollectorFee;
        assertEq(dai.balanceOf(feeReceiver), 0);
        // There is no need for approval as factory holds the shares of fees.
        factory.withdrawAllFees(feeReceiver);
        assertEq(dai.balanceOf(feeReceiver), feeReceiverFee);
        assertEq(daiVault.balanceOf(feeReceiver), 0);
        assertEq(factory.collectedFees(feeReceiver, address(dai)), 0);
    }

    function test_pauseVault_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.pauseVault(address(dai));
    }

    function test_pauseVault() external {
        vm.prank(manager);
        factory.pauseVault(address(dai));
        assertEq(daiVault.paused(), true);
    }

    function test_unpauseVault_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.unpauseVault(address(dai));
    }

    function test_unpauseVault() external {
        vm.startPrank(manager);
        factory.pauseVault(address(dai));
        factory.unpauseVault(address(dai));
        assertEq(daiVault.paused(), false);
        vm.stopPrank();
    }

    function test_factoryPause_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.pause();
    }

    function test_factoryUnPause_failsWithoutManager() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), MANAGER_ROLE
            )
        );
        factory.unpause();
    }

    function test_factoryPause_failsWhenAlreadyPaused() external {
        vm.startPrank(manager);
        factory.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        factory.pause();
        vm.stopPrank();
    }

    function test_factoryUnPause_failsWhenAlreadyUnpaused() external {
        vm.prank(manager);
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        factory.unpause();
    }

    function test_factoryPause() external {
        vm.prank(manager);
        factory.pause();
        assertEq(factory.paused(), true);
    }

    function test_factoryUnpause() external {
        vm.startPrank(manager);
        factory.pause();
        factory.unpause();
        assertEq(factory.paused(), false);
        vm.stopPrank();
    }

    function test_IntegrationTest() external {
        uint256 daiToMint = 100e18;
        dai.approve(address(factory), daiToMint);
        // mint honey with 100 dai
        uint256 honeyToMint = factory.mint(address(dai), daiToMint, address(this));
        for (uint256 i = 0; i < 10; i++) {
            factory.redeem(address(dai), honeyToMint / 10, address(this));
            if (i == 5) {
                // change redeem rate to 1e18
                vm.startPrank(manager);
                factory.setRedeemRate(address(dai), 98e16);
                // change polFeeCollectorFeeRate to 0
                factory.setPOLFeeCollectorFeeRate(0);
                vm.stopPrank();
            }
        }
        // redeem rest of the honey
        uint256 remainingHoney = honeyToMint - (honeyToMint / 10) * 10;
        factory.redeem(address(dai), remainingHoney, address(this));
        // at this point shares should be of fees only
        assertEq(
            daiVault.balanceOf(address(factory)),
            factory.collectedFees(feeReceiver, address(dai)) + factory.collectedFees(polFeeCollector, address(dai))
        );
        factory.withdrawAllFees(feeReceiver);
        factory.withdrawAllFees(polFeeCollector);
        // factory should not have any shares of daiVault left.
        assertEq(daiVault.balanceOf(address(factory)), 0);
    }

    function testFuzz_InflationAttack(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 1, (type(uint256).max - daiBalance) / 2);
        address attacker = makeAddr("attacker");
        // Attacker donates USDC to the vault to change the exchange rate.
        dai.mint(attacker, 2 * _daiToMint);
        vm.prank(attacker);
        dai.transfer(address(daiVault), _daiToMint);
        assertEq(dai.balanceOf(address(daiVault)), _daiToMint); // assets
        assertEq(daiVault.totalSupply(), 0); // shares
        // assets/shares exchange rate = 1 when there is no shares in the vault.
        assertEq(daiVault.convertToShares(_daiToMint), _daiToMint);

        vm.startPrank(attacker);
        dai.approve(address(daiVault), _daiToMint);
        // Attacker cannot mint shares, so no inflation attacks happen.
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        daiVault.deposit(_daiToMint, address(this));
        vm.stopPrank();
        // If inflation attacks happen, the exchange rate will be 0.5.
        assertFalse(dai.balanceOf(address(daiVault)) == 2 * _daiToMint); // assets
        assertFalse(daiVault.totalSupply() == _daiToMint); // shares
        assertFalse(daiVault.convertToShares(_daiToMint) == _daiToMint / 2); // assets/shares exchange rate = 0.5
        // As inflation attacks do not happen, the exchange rate is still 1.
        assertEq(dai.balanceOf(address(daiVault)), _daiToMint); // assets
        assertEq(daiVault.totalSupply(), 0); // shares
        assertEq(daiVault.convertToShares(_daiToMint), _daiToMint); // assets/shares exchange rate = 1

        vm.startPrank(attacker);
        dai.approve(address(factory), _daiToMint);
        // Attacker mints Honey with USDC to increase the total supply of shares.
        factory.mint(address(dai), _daiToMint, address(this));
        vm.stopPrank();
        assertEq(dai.balanceOf(address(daiVault)), 2 * _daiToMint); // vault assets
        assertEq(daiVault.totalSupply(), _daiToMint); // shares
        assertEq(daiVault.convertToShares(_daiToMint), _daiToMint); // assets/shares exchange rate = 1
    }

    function testFuzz_PreviewRequiredCollateral(uint128 _mintedHoneys) external {
        uint256 shareReq = (uint256(_mintedHoneys) * 1e18) / daiMintRate;
        uint256 requiredCollateral = factory.previewRequiredCollateral(address(dai), _mintedHoneys);
        assertEq(requiredCollateral, shareReq);
    }

    function testFuzz_PreviewHoneyToRedeem(uint64 _redeemedDai) external {
        uint256 redeemedHoneys = (daiVault.previewWithdraw(_redeemedDai) * 1e18) / daiRedeemRate;
        uint256 honeyToRedeem = factory.previewHoneyToRedeem(address(dai), _redeemedDai);
        assertEq(honeyToRedeem, redeemedHoneys);
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
        address newImplementation = address(new MockVault());
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        // implementation update of the beacon fails as caller is not the owner.
        vm.expectRevert(UpgradeableBeacon.Unauthorized.selector);
        beacon.upgradeTo(newImplementation);
    }

    function test_UpgradeBeaconProxyToFaultyVault() public {
        address newImplementation = address(new FaultyVault());
        UpgradeableBeacon beacon = UpgradeableBeacon(factory.beacon());
        vm.startPrank(governance);
        beacon.upgradeTo(newImplementation);
        assertEq(beacon.implementation(), newImplementation);
        // Due to storage collision, asset will fetch the name instead of the asset address.
        assertNotEq(FaultyVault(address(daiVault)).asset(), address(dai));
        address oldImplementation = address(new CollateralVault());
        beacon.upgradeTo(oldImplementation);
        assertEq(beacon.implementation(), oldImplementation);
        // After downgrading the implementation, asset will fetch the correct asset address.
        assertEq(daiVault.asset(), address(dai));
    }

    function test_UpgradeBeaconProxy() public returns (address beacon) {
        address newImplementation = address(new MockVault());
        // update the implementation of the beacon
        beacon = factory.beacon();
        vm.prank(governance);
        // update the implementation of the beacon
        UpgradeableBeacon(beacon).upgradeTo(newImplementation);
        // check the new implementation of the beacon
        assertEq(UpgradeableBeacon(beacon).implementation(), newImplementation);
        assertEq(MockVault(address(daiVault)).VERSION(), 2);
        // no storage collision, asset will fetch the correct asset address.
        assertEq(daiVault.asset(), address(dai));
        assertEq(MockVault(address(daiVault)).isNewImplementation(), true);
    }

    function test_UpgradeAndDowngradeOfBeaconProxy() public {
        address beacon = test_UpgradeBeaconProxy();
        // downgrade the implementation of the beacon
        address oldImplementation = address(new CollateralVault());
        vm.prank(governance);
        UpgradeableBeacon(beacon).upgradeTo(oldImplementation);
        assertEq(UpgradeableBeacon(beacon).implementation(), oldImplementation);
        // Call will revert as old implementation does not have isNewImplementation function.
        vm.expectRevert();
        MockVault(address(daiVault)).isNewImplementation();
    }

    function _initialMint(uint256 _daiToMint) internal returns (uint256 mintedHoneys) {
        mintedHoneys = _initialMintToAParticularReceiver(_daiToMint, receiver);
    }

    function _initialMintToAParticularReceiver(
        uint256 _daiToMint,
        address _receiver
    )
        internal
        returns (uint256 mintedHoneys)
    {
        mintedHoneys = (_daiToMint * daiMintRate) / 1e18;
        dai.approve(address(factory), _daiToMint);
        factory.mint(address(dai), _daiToMint, _receiver);
    }

    function _verifyOutputOfMint(
        ERC20 _token,
        CollateralVault _tokenVault,
        uint256 _tokenBal,
        uint256 _tokenToMint,
        uint256 _mintedHoneys
    )
        internal
    {
        assertEq(factory.previewMint(address(_token), _tokenToMint), _mintedHoneys);
        assertEq(_token.balanceOf(address(this)), _tokenBal - _tokenToMint);
        assertEq(_token.balanceOf(address(_tokenVault)), _tokenToMint);
        assertEq(honey.totalSupply(), _mintedHoneys);
        assertEq(honey.balanceOf(receiver), _mintedHoneys);
        assertEq(_tokenVault.balanceOf(address(factory)), _tokenVault.convertToShares(_tokenToMint));
        assertEq(_tokenVault.balanceOf(feeReceiver), 0);
    }

    function _verifyOutputOfRedeem(
        ERC20 _token,
        CollateralVault _tokenVault,
        uint256 _tokenBal,
        uint256 _tokenToMint,
        uint256 _mintedShares,
        uint256 _redeemedToken,
        uint256 _honeyToRedeem
    )
        internal
    {
        uint256 mintedHoneys = (_mintedShares * factory.getMintRate(address(_token))) / 1e18;
        uint256 redeemedShares = (_honeyToRedeem * factory.getRedeemRate(address(_token))) / 1e18;
        assertEq(_token.balanceOf(address(_tokenVault)), _tokenToMint - _redeemedToken);
        assertEq(_token.balanceOf(address(this)), _tokenBal - _tokenToMint + _redeemedToken);
        assertEq(honey.balanceOf(receiver), mintedHoneys - _honeyToRedeem);
        assertEq(honey.totalSupply(), mintedHoneys - _honeyToRedeem);
        assertEq(_tokenVault.balanceOf(address(factory)), _mintedShares - redeemedShares);
        assertEq(_tokenVault.totalSupply(), _mintedShares - redeemedShares);
        assertEq(_tokenVault.balanceOf(feeReceiver), 0);
    }
}
