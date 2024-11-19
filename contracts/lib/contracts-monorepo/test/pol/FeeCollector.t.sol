// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Test } from "forge-std/Test.sol";
import { LibClone } from "solady/src/utils/LibClone.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { MockERC20 } from "@mock/token/MockERC20.sol";
import { FeeCollector } from "src/pol/FeeCollector.sol";
import { IFeeCollector, IPOLErrors } from "src/pol/interfaces/IFeeCollector.sol";
import { POLTest } from "./POL.t.sol";

contract FeeCollectorTest is POLTest {
    MockERC20 internal feeToken;

    bytes32 internal defaultAdminRole;
    bytes32 internal managerRole;

    address internal manager = makeAddr("manager");

    function setUp() public override {
        super.setUp();

        feeToken = new MockERC20();
        deal(address(feeToken), address(this), 100 ether);
        deal(address(wbera), address(this), 100 ether);

        defaultAdminRole = feeCollector.DEFAULT_ADMIN_ROLE();
        managerRole = feeCollector.MANAGER_ROLE();

        vm.prank(governance);
        feeCollector.grantRole(managerRole, manager);
    }

    function test_GovernanceIsOwner() public view {
        assert(feeCollector.hasRole(defaultAdminRole, governance));
    }

    function test_Initialize_FailsIfGovernanceAddrIsZero() public {
        FeeCollector feeCollectorNew = _deployNewFeeCollector();
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        feeCollectorNew.initialize(address(0), address(wbera), address(bgtStaker), PAYOUT_AMOUNT);
    }

    function test_Initialize_FailsIfPayoutTokenAddrIsZero() public {
        FeeCollector feeCollectorNew = _deployNewFeeCollector();
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        feeCollectorNew.initialize(governance, address(0), address(bgtStaker), PAYOUT_AMOUNT);
    }

    function test_Initialize_FailsIfRewardReceiverAddrIsZero() public {
        FeeCollector feeCollectorNew = _deployNewFeeCollector();
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        feeCollectorNew.initialize(governance, address(wbera), address(0), PAYOUT_AMOUNT);
    }

    function test_Initialize_FailsIfPayoutAmountIsZero() public {
        FeeCollector feeCollectorNew = _deployNewFeeCollector();
        vm.expectRevert(IPOLErrors.PayoutAmountIsZero.selector);
        feeCollectorNew.initialize(governance, address(wbera), address(bgtStaker), 0);
    }

    function test_SetPayoutToken_FailsIfNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdminRole
            )
        );
        feeCollector.setPayoutToken(address(wbera));
    }

    function test_SetPayoutToken_FailsIfZeroAddr() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.ZeroAddress.selector);
        feeCollector.setPayoutToken(address(0));
    }

    function test_SetPayoutToken() public {
        MockERC20 newPayoutToken = new MockERC20();
        testFuzz_setPayoutToken(address(newPayoutToken));
    }

    function testFuzz_setPayoutToken(address newPayoutToken) public {
        vm.assume(newPayoutToken != address(0));
        vm.prank(governance);
        vm.expectEmit();
        emit IFeeCollector.PayoutTokenSet(address(wbera), newPayoutToken);
        feeCollector.setPayoutToken(newPayoutToken);
        assertEq(feeCollector.payoutToken(), newPayoutToken);
    }

    function test_SetPayoutAmount_FailsIfNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdminRole
            )
        );
        feeCollector.setPayoutAmount(2 ether);
    }

    function test_SetPayoutAmount_FailsIfZero() public {
        vm.prank(governance);
        vm.expectRevert(IPOLErrors.PayoutAmountIsZero.selector);
        feeCollector.setPayoutAmount(0);
    }

    function test_SetPayoutAmount() public {
        testFuzz_SetPayoutAmount(1 ether);
    }

    function testFuzz_SetPayoutAmount(uint256 newPayoutAmount) public {
        newPayoutAmount = _bound(newPayoutAmount, 1, type(uint256).max);
        vm.prank(governance);
        vm.expectEmit();
        emit IFeeCollector.PayoutAmountSet(PAYOUT_AMOUNT, newPayoutAmount);
        feeCollector.setPayoutAmount(newPayoutAmount);
        assertEq(feeCollector.payoutAmount(), newPayoutAmount);
    }

    function test_ClaimFees_FailsIfNotApproved() public {
        _addFees();
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(feeToken);
        feeCollector.claimFees(address(this), feeTokens);
    }

    function test_ClaimFees_FailsIfPaused() public {
        _addFees();
        test_Pause();
        wbera.approve(address(feeCollector), 100 ether);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(feeToken);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        feeCollector.claimFees(address(this), feeTokens);
    }

    function test_ClaimFees() public {
        _addFees();
        wbera.approve(address(feeCollector), 100 ether);
        address[] memory feeTokens = new address[](1);
        feeTokens[0] = address(feeToken);
        vm.expectEmit();
        emit IFeeCollector.FeesClaimed(address(this), address(this), address(feeToken), 10 ether);
        feeCollector.claimFees(address(this), feeTokens);
        assertEq(feeToken.balanceOf(address(feeCollector)), 0);
        assertEq(feeToken.balanceOf(address(this)), 100 ether);
        assertEq(wbera.balanceOf(address(bgtStaker)), 1 ether);
    }

    function test_Donate_FailsIfAmountLessThanPayoutAmount() public {
        testFuzz_Donate_FailsIfAmountLessThanPayoutAmount(0.5 ether);
    }

    function testFuzz_Donate_FailsIfAmountLessThanPayoutAmount(uint256 amount) public {
        amount = _bound(amount, 0, PAYOUT_AMOUNT - 1);
        vm.expectRevert(IPOLErrors.DonateAmountLessThanPayoutAmount.selector);
        feeCollector.donate(amount);
    }

    function test_Donate_FailsIfNotApproved() public {
        testFuzz_Donate_FailsIfNotApproved(10 ether);
    }

    function testFuzz_Donate_FailsIfNotApproved(uint256 amount) public {
        amount = _bound(amount, PAYOUT_AMOUNT, type(uint256).max);
        wbera.approve(address(feeCollector), amount - 1);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        feeCollector.donate(amount);
    }

    function test_Donate() public {
        testFuzz_Donate(10 ether);
    }

    function testFuzz_Donate(uint256 amount) public {
        amount = _bound(amount, PAYOUT_AMOUNT, type(uint256).max);
        deal(address(wbera), address(this), amount);
        wbera.approve(address(feeCollector), amount);
        vm.expectEmit();
        emit IFeeCollector.PayoutDonated(address(this), amount);
        feeCollector.donate(amount);
        assertEq(wbera.balanceOf(address(this)), 0);
        assertEq(wbera.balanceOf(address(bgtStaker)), amount);
        assertEq(wbera.balanceOf(address(feeCollector)), 0);
    }

    function _addFees() internal {
        feeToken.transfer(address(feeCollector), 10 ether);
        assertEq(feeToken.balanceOf(address(feeCollector)), 10 ether);
    }

    function _deployNewFeeCollector() internal returns (FeeCollector feeCollectorNew) {
        feeCollectorNew = FeeCollector(LibClone.deployERC1967(address(new FeeCollector())));
    }

    function test_Pause_FailIfNotVaultManager() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), managerRole
            )
        );
        feeCollector.pause();
    }

    function test_Pause() public {
        vm.prank(manager);
        feeCollector.pause();
        assertTrue(feeCollector.paused());
    }

    function test_Unpause_FailIfNotVaultManager() public {
        test_Pause();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), managerRole
            )
        );
        feeCollector.unpause();
    }

    function test_Unpause() public {
        vm.startPrank(manager);
        feeCollector.pause();
        feeCollector.unpause();
        assertFalse(feeCollector.paused());
    }
}
