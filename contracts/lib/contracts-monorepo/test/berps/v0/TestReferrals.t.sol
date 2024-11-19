// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { LibClone } from "solady/src/utils/LibClone.sol";

import "src/berps/core/v0/Referrals.sol";

import { BerpsErrors } from "src/berps/utils/BerpsErrors.sol";

import "@mock/berps/MockOrders.sol";

contract TestReferrals is Test {
    Referrals referrals;
    MockOrders orders;

    address settlement = address(0x69);
    address gov = address(0x42);

    address user1 = address(0x11);
    address user2 = address(0x22);
    address user3 = address(0x33);

    function setUp() public {
        orders = new MockOrders(settlement, gov);
        Referrals _ref = new Referrals();
        address refProxy = LibClone.deployERC1967(address(_ref));
        referrals = Referrals(refProxy);
        referrals.initialize(address(orders), 50, 20, 10_000e18);

        orders.setBalance(address(orders), 100e18);
        orders.setBalance(user1, 100e18);
        orders.setBalance(user2, 100e18);
        orders.setBalance(user3, 100e18);
    }

    function testReferralE2E() public {
        // users' referral fee should be 10% of open fee
        assertEq(referrals.getPercentOfOpenFeeP(user1), 10e10);
        assertEq(referrals.getPercentOfOpenFeeP(user2), 10e10);

        // user 2 registers user 1 as referrer (user 1 refers user2)
        vm.startPrank(user2, user2);
        referrals.registerPotentialReferrer(user1);

        // user 3 CANNOT refer user 2 (since user 2 has already been referred by user 1)
        vm.expectRevert(BerpsErrors.AlreadyReferred.selector);
        referrals.registerPotentialReferrer(user3);
        vm.stopPrank();

        // user 1 --> user 2 relationship should be in the contract
        assertEq(referrals.getTraderReferrer(user2), user1);
        IReferrals.ReferrerDetails memory ref1 = referrals.getReferrerDetails(user1);
        assertEq(ref1.tradersReferred[0], user2);

        // user 2 now completes a trade --> user 1 should earn fees
        vm.startPrank(settlement, user2);
        referrals.distributePotentialReward(user2, 100e18, 10e10);
        vm.stopPrank();
        assertEq(orders.balanceOf(user1), 102e18); // earned 2% of 100e18
        assertEq(orders.balanceOf(address(orders)), 98e18);

        // try referring in a loop, should revert
        assertEq(referrals.getTraderReferrer(user1), address(0));
        vm.startPrank(user1, user1);

        // user 2 CANNOT refer user 1
        vm.expectRevert(BerpsErrors.ReferralCycle.selector);
        referrals.registerPotentialReferrer(user2);

        // user 1 CANNOT refer user 1
        vm.expectRevert(BerpsErrors.InvalidReferrer.selector);
        referrals.registerPotentialReferrer(user1);

        // user 3 refers user 1 (someone who has already referred)
        referrals.registerPotentialReferrer(user3);
        assertEq(referrals.getTraderReferrer(user1), user3);
        vm.stopPrank();

        // user 1 now completes a trade --> user 3 earns fees
        vm.startPrank(settlement, user1);
        referrals.distributePotentialReward(user1, 100e18, 10e10);
        vm.stopPrank();
        assertEq(orders.balanceOf(user3), 102e18); // earned 2% of 100e18
    }
}
