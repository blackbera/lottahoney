// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { ERC4626 } from "solady/src/tokens/ERC4626.sol";

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IHoneyErrors } from "src/honey/IHoneyErrors.sol";
import { HoneyBaseTest } from "./HoneyBase.t.sol";

contract CollateralVaultTest is HoneyBaseTest {
    function test_vaultParams() external {
        assertEq(daiVault.name(), "MockDAIVault");
        assertEq(daiVault.symbol(), "DAIVault");
        assertEq(daiVault.asset(), address(dai));
        assertEq(daiVault.factory(), address(factory));
    }

    function test_pausingVault_failsIfNotFactory() external {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        daiVault.pause();
    }

    function test_pauseVault_succeedsWithCorrectSender() external {
        vm.prank(address(factory));
        daiVault.pause();
        assertEq(daiVault.paused(), true);
    }

    function test_unpausingVault_failsIfNotFactory() external {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        daiVault.unpause();
    }

    function test_unpausingVault_succeedsWithCorrectSender() external {
        vm.startPrank(address(factory));
        daiVault.pause();
        daiVault.unpause();
        assertEq(daiVault.paused(), false);
    }

    function test_deposit_withOutOwner() external {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        uint256 daiToMint = 100e18;
        daiVault.deposit(daiToMint, address(this));
    }

    function test_deposit_whileItsPaused() external {
        uint256 daiToMint = 100e18;
        vm.prank(address(factory));
        daiVault.pause();
        vm.prank(address(factory));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        daiVault.deposit(daiToMint, address(this));
    }

    function testFuzz_deposit_succeedsWithCorrectSender(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 0, daiBalance);
        dai.transfer(address(factory), _daiToMint);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), _daiToMint);
        daiVault.deposit(_daiToMint, address(this));
        assertEq(daiVault.balanceOf(address(this)), _daiToMint);
        assertEq(dai.balanceOf(address(daiVault)), _daiToMint);
        assertEq(dai.balanceOf(address(this)), daiBalance - _daiToMint);
    }

    function testFuzz_depositIntoUSTVault(uint256 _usdtToMint) external {
        _usdtToMint = _bound(_usdtToMint, 0, usdtBalance);
        uint256 honeyOverUsdtRate = 1e12;
        usdt.transfer(address(factory), _usdtToMint);
        vm.startPrank(address(factory));
        usdt.approve(address(usdtVault), _usdtToMint);
        usdtVault.deposit(_usdtToMint, address(this));
        assertEq(usdtVault.balanceOf(address(this)), _usdtToMint * honeyOverUsdtRate);
        assertEq(usdt.balanceOf(address(usdtVault)), _usdtToMint);
        assertEq(usdt.balanceOf(address(this)), usdtBalance - _usdtToMint);
    }

    function test_deposit() external {
        uint256 daiToMint = 100e18;
        dai.transfer(address(factory), daiToMint);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), daiToMint);
        daiVault.deposit(daiToMint, address(this));
        assertEq(daiVault.balanceOf(address(this)), daiToMint);
        assertEq(dai.balanceOf(address(daiVault)), daiToMint);
        assertEq(dai.balanceOf(address(this)), daiBalance - daiToMint);
    }

    function test_mint_failsWithIncorrectSender() external {
        uint256 daiToMint = 100e18;
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        daiVault.mint(daiToMint, receiver);
    }

    function test_mint_whileItsPaused() external {
        uint256 daiToMint = 100e18;
        vm.prank(address(factory));
        daiVault.pause();
        vm.prank(address(factory));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        daiVault.mint(daiToMint, address(this));
    }

    function testFuzz_mint_succeedsWithCorrectSender(uint256 _daiToMint) external {
        _daiToMint = _bound(_daiToMint, 0, daiBalance);
        uint256 honeySupplyBefore = honey.totalSupply();
        dai.transfer(address(factory), _daiToMint);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), _daiToMint);
        daiVault.mint(_daiToMint, receiver);
        assertEq(honey.totalSupply(), honeySupplyBefore); //No Honey will be minted
        assertEq(daiVault.balanceOf(receiver), _daiToMint);
        assertEq(daiVault.balanceOf(feeReceiver), 0);
    }

    function testFuzz_mintFromUSTVault(uint256 _usdtToMint) external {
        _usdtToMint = _bound(_usdtToMint, 0, usdtBalance);
        uint256 honeyOverUsdtRate = 1e12;
        usdt.transfer(address(factory), _usdtToMint);
        vm.startPrank(address(factory));
        usdt.approve(address(usdtVault), _usdtToMint);
        //shares amount is passed as the input for mint function
        usdtVault.mint(_usdtToMint * honeyOverUsdtRate, receiver);
        assertEq(usdtVault.balanceOf(receiver), _usdtToMint * honeyOverUsdtRate);
        assertEq(usdt.balanceOf(address(usdtVault)), _usdtToMint);
        assertEq(usdt.balanceOf(address(this)), usdtBalance - _usdtToMint);
    }

    function test_mint() external {
        uint256 daiToMint = 100e18;
        dai.transfer(address(factory), daiToMint);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), daiToMint);
        daiVault.mint(daiToMint, receiver);
        assertEq(daiVault.balanceOf(receiver), daiToMint);
        assertEq(dai.balanceOf(address(daiVault)), daiToMint);
        assertEq(dai.balanceOf(address(this)), daiBalance - daiToMint);
    }

    function testFuzz_withdraw_failsWithIncorrectSender(uint128 _daiToWithdraw) external {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        daiVault.withdraw(_daiToWithdraw, receiver, receiver);
    }

    function testFuzz_withdraw_failsWithInsufficientBalance(uint256 _daiToWithdraw) external {
        _daiToWithdraw = _bound(_daiToWithdraw, 1, type(uint256).max);
        vm.prank(address(factory));
        vm.expectRevert(ERC4626.WithdrawMoreThanMax.selector);
        //receiver does not have enough shares to withdraw
        daiVault.withdraw(_daiToWithdraw, receiver, receiver);
    }

    function test_withdraw_whileItsPaused() external {
        uint256 redeemedDai = 100e18;
        vm.prank(address(factory));
        daiVault.pause();
        vm.prank(address(factory));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        daiVault.withdraw(redeemedDai, address(this), address(this));
    }

    function testFuzz_withdraw_failsWithInsufficientAllowance(uint256 _daiToWithdraw) external {
        uint256 daiToMint = 100e18;
        _daiToWithdraw = _bound(_daiToWithdraw, 1, daiToMint);
        dai.transfer(address(factory), daiToMint);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), daiToMint);
        daiVault.mint(daiToMint, receiver);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        daiVault.withdraw(_daiToWithdraw, receiver, receiver);
    }

    function testFuzz_withdraw_succeedsWithCorrectSender(uint256 _daiToWithdraw) external {
        uint256 daiToMint = 100e18;
        _daiToWithdraw = _bound(_daiToWithdraw, 0, daiToMint);
        dai.transfer(address(factory), daiToMint);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), daiToMint);
        daiVault.mint(daiToMint, address(factory));
        assertEq(daiVault.balanceOf(address(factory)), daiToMint);
        daiVault.withdraw(_daiToWithdraw, receiver, address(factory));
        assertEq(daiVault.balanceOf(address(factory)), daiToMint - _daiToWithdraw);
        assertEq(dai.balanceOf(receiver), _daiToWithdraw);
    }

    function testFuzz_withdrawFromUSTVault(uint256 _usdtToWithdraw) external {
        uint256 usdtToMint = 100e6;
        uint256 honeyOverUsdtRate = 1e12;
        _usdtToWithdraw = _bound(_usdtToWithdraw, 0, usdtToMint);
        usdt.transfer(address(factory), usdtToMint);
        vm.startPrank(address(factory));
        usdt.approve(address(usdtVault), usdtToMint);
        usdtVault.deposit(usdtToMint, address(factory));
        assertEq(usdtVault.balanceOf(address(factory)), usdtToMint * honeyOverUsdtRate);
        usdtVault.withdraw(_usdtToWithdraw, receiver, address(factory));
        assertEq(
            usdtVault.balanceOf(address(factory)), usdtToMint * honeyOverUsdtRate - _usdtToWithdraw * honeyOverUsdtRate
        );
        assertEq(usdt.balanceOf(receiver), _usdtToWithdraw);
    }

    function test_withdraw() external {
        uint256 redeemedDai = 100e18;
        dai.transfer(address(factory), redeemedDai);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), redeemedDai);
        daiVault.mint(redeemedDai, address(factory));
        assertEq(daiVault.balanceOf(address(factory)), redeemedDai);
        daiVault.withdraw(redeemedDai, receiver, address(factory));
        assertEq(daiVault.balanceOf(address(factory)), 0);
        assertEq(dai.balanceOf(receiver), redeemedDai);
    }

    function test_redeem_withOutOwner() external {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        uint256 redeemedDai = 100e18;
        daiVault.redeem(redeemedDai, address(this), address(this));
    }

    function test_redeem_whileItsPaused() external {
        uint256 redeemedDai = 100e18;
        vm.prank(address(factory));
        daiVault.pause();
        vm.prank(address(factory));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        daiVault.redeem(redeemedDai, address(this), address(this));
    }

    function testFuzz_redeem_failsWithInsufficientBalance(uint256 _redeemedDai) external {
        _redeemedDai = _bound(_redeemedDai, 1, type(uint256).max);
        vm.prank(address(factory));
        vm.expectRevert(ERC4626.RedeemMoreThanMax.selector);
        //receiver does not have enough shares to redeem
        daiVault.redeem(_redeemedDai, receiver, receiver);
    }

    function testFuzz_redeem_failWithInsufficientAllowance(uint256 _redeemedDai) external {
        uint256 daiToMint = 100e18;
        _redeemedDai = _bound(_redeemedDai, 1, daiToMint);
        dai.transfer(address(factory), daiToMint);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), daiToMint);
        daiVault.mint(daiToMint, receiver);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        daiVault.redeem(_redeemedDai, receiver, receiver);
    }

    function testFuzz_redeem_succeedsWithCorrectSender(uint256 _redeemedDai) external {
        uint256 daiToMint = 100e18;
        _redeemedDai = _bound(_redeemedDai, 0, daiToMint);
        dai.transfer(address(factory), daiToMint);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), daiToMint);
        daiVault.mint(daiToMint, address(factory));
        assertEq(daiVault.balanceOf(address(factory)), daiToMint);
        daiVault.redeem(_redeemedDai, receiver, address(factory));
        assertEq(daiVault.balanceOf(address(factory)), daiToMint - _redeemedDai);
        assertEq(dai.balanceOf(receiver), _redeemedDai);
    }

    function testFuzz_redeemFromUSTVault(uint256 _redeemedUsdt) external {
        uint256 usdtToMint = 100e6;
        uint256 honeyOverUsdtRate = 1e12;
        _redeemedUsdt = _bound(_redeemedUsdt, 0, usdtToMint);
        usdt.transfer(address(factory), usdtToMint);
        vm.startPrank(address(factory));
        usdt.approve(address(usdtVault), usdtToMint);
        usdtVault.deposit(usdtToMint, address(factory));
        assertEq(usdtVault.balanceOf(address(factory)), usdtToMint * honeyOverUsdtRate);
        //redeem function takes shares as input
        usdtVault.redeem(_redeemedUsdt * honeyOverUsdtRate, receiver, address(factory));
        assertEq(
            usdtVault.balanceOf(address(factory)), usdtToMint * honeyOverUsdtRate - _redeemedUsdt * honeyOverUsdtRate
        );
        assertEq(usdt.balanceOf(receiver), _redeemedUsdt);
    }

    function test_redeem() external {
        uint256 redeemedDai = 100e18;
        dai.transfer(address(factory), redeemedDai);
        vm.startPrank(address(factory));
        dai.approve(address(daiVault), redeemedDai);
        daiVault.deposit(redeemedDai, (address(factory)));
        assertEq(daiVault.balanceOf((address(factory))), redeemedDai);
        daiVault.redeem(redeemedDai, receiver, address(factory));
        assertEq(daiVault.balanceOf(address(factory)), 0);
        assertEq(dai.balanceOf(receiver), redeemedDai);
    }
}
