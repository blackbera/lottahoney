// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { StdCheats } from "forge-std/StdCheats.sol";
import { SoladyTest } from "solady/test/utils/SoladyTest.sol";

import { ERC1967Utils } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { ERC20 } from "solady/src/tokens/ERC20.sol";
import { LibClone } from "solady/src/utils/LibClone.sol";

import { IHoneyErrors } from "src/honey/IHoneyErrors.sol";
import { Honey } from "src/honey/Honey.sol";
import { HoneyDeployer } from "src/honey/HoneyDeployer.sol";
import { HoneyFactory } from "src/honey/HoneyFactory.sol";
import { MockHoney } from "@mock/honey/MockHoney.sol";

contract HoneyTest is StdCheats, SoladyTest {
    struct _TestTemps {
        address owner;
        address to;
        uint256 amount;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 privateKey;
        uint256 nonce;
    }

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    address internal governance = makeAddr("governance");
    address internal feeReceiver = makeAddr("feeReceiver");
    address internal polFeeCollector = makeAddr("polFeeCollector");
    // address used to test transfer and transferFrom
    address internal spender = makeAddr("spender");
    Honey internal honey;
    HoneyDeployer internal deployer;
    HoneyFactory internal factory;

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        deployer = new HoneyDeployer(governance, feeReceiver, polFeeCollector, 0, 1);
        honey = deployer.honey();
        factory = deployer.honeyFactory();
        assertEq(honey.hasRole(factory.DEFAULT_ADMIN_ROLE(), governance), true);
    }

    function test_MetaData() public {
        assertEq(honey.name(), "Honey");
        assertEq(honey.symbol(), "HONEY");
        assertEq(honey.decimals(), 18);
    }

    /// @dev Test that minting Honey fails if the caller is not the factory.
    function test_Mint_FailIfNotFactory() public {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        honey.mint(address(this), 100);
    }

    /// @dev Test that minting Honey fails if the total supply overflows.
    function testFuzz_Mint_TotalSupplyOverflow(uint256 amount0, uint256 amount1) public {
        vm.assume(amount0 > 0);
        amount1 = _bound(amount1, type(uint256).max - amount0 + 1, type(uint256).max);
        vm.startPrank(address(factory));
        honey.mint(address(this), amount0);
        vm.expectRevert(ERC20.TotalSupplyOverflow.selector);
        honey.mint(address(this), amount1);
    }

    /// @dev Test minting Honey
    function test_Mint() public {
        testFuzz_Mint(100);
    }

    /// @dev Test minting Honey
    function testFuzz_Mint(uint256 mintAmount) public {
        vm.expectEmit();
        emit ERC20.Transfer(address(0), address(this), mintAmount);
        vm.prank(address(factory));
        honey.mint(address(this), mintAmount);
        assertEq(honey.balanceOf(address(this)), mintAmount);
        assertEq(honey.totalSupply(), mintAmount);
    }

    /// @dev Test that burning Honey fails if the caller is not the factory.
    function test_Burn_FailIfNotFactory() public {
        vm.expectRevert(IHoneyErrors.NotFactory.selector);
        honey.burn(address(this), 100);
    }

    /// @dev Test that burning Honey fails if there is insufficient balance.
    function test_Burn_FailIfInsufficientBalance() public {
        testFuzz_Burn_FailIfInsufficientBalance(0, 50);
    }

    /// @dev Test that burning Honey fails if there is insufficient balance.
    function testFuzz_Burn_FailIfInsufficientBalance(uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(burnAmount > 0);
        mintAmount = _bound(mintAmount, 0, burnAmount - 1);
        testFuzz_Mint(mintAmount);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        vm.prank(address(factory));
        honey.burn(address(this), burnAmount);
    }

    /// @dev Test burning Honey
    function test_Burn() public {
        testFuzz_Burn(100, 50);
    }

    /// @dev Test burning Honey
    function testFuzz_Burn(uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(mintAmount > 0);
        burnAmount = _bound(burnAmount, 0, mintAmount);
        testFuzz_Mint(mintAmount);

        vm.expectEmit();
        emit ERC20.Transfer(address(this), address(0), burnAmount);
        vm.prank(address(factory));
        honey.burn(address(this), burnAmount);
        assertEq(honey.balanceOf(address(this)), mintAmount - burnAmount);
        assertEq(honey.totalSupply(), mintAmount - burnAmount);
    }

    function test_Approve() public {
        testFuzz_Approve(spender, 1e18);
    }

    function testFuzz_Approve(address _spender, uint256 amount) public {
        vm.expectEmit();
        emit ERC20.Approval(address(this), _spender, amount);
        assertTrue(honey.approve(_spender, amount));

        assertEq(honey.allowance(address(this), _spender), amount);
    }

    function test_Transfer_FailsIfInsufficientBalance() public {
        testFuzz_Transfer_FailsIfInsufficientBalance(governance, 2e18);
    }

    function testFuzz_Transfer_FailsIfInsufficientBalance(address to, uint256 amount) public {
        testFuzz_Mint(1e18);
        amount = _bound(amount, 1e18 + 1, type(uint256).max);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        honey.transfer(to, amount);
    }

    function test_Transfer() public {
        testFuzz_Transfer(governance, 1e18);
    }

    function testFuzz_Transfer(address to, uint256 amount) public {
        vm.assume(to != address(this));
        testFuzz_Mint(amount);
        vm.expectEmit();
        emit ERC20.Transfer(address(this), to, amount);
        assertTrue(honey.transfer(to, amount));
        assertEq(honey.totalSupply(), amount);
        assertEq(honey.balanceOf(address(this)), 0);
        assertEq(honey.balanceOf(to), amount);
    }

    function test_TransferFrom_FailsIfInsufficientAllowance() public {
        testFuzz_TransferFrom_FailsIfInsufficientAllowance(governance, 1e18);
    }

    function testFuzz_TransferFrom_FailsIfInsufficientAllowance(address to, uint256 amount) public {
        vm.assume(amount > 0);
        testFuzz_Mint(amount);
        // address(this) approves randomCaller to spend (amount - 1) Honey.
        honey.approve(spender, amount - 1);
        vm.prank(spender);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        honey.transferFrom(address(this), to, amount);
    }

    function test_TransferFrom_FailsIfInsufficientBalance() public {
        testFuzz_TransferFrom_FailsIfInsufficientBalance(governance, 1e18);
    }

    function testFuzz_TransferFrom_FailsIfInsufficientBalance(address to, uint256 amount) public {
        vm.assume(amount > 0);
        testFuzz_Mint(amount - 1);
        // address(this) approves spender to spend amount Honey.
        honey.approve(spender, amount);
        vm.prank(spender);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        honey.transferFrom(address(this), to, amount);
    }

    function test_TransferFrom() public {
        testFuzz_TransferFrom(governance, 1e18);
    }

    function testFuzz_TransferFrom(address to, uint256 amount) public {
        vm.assume(to != address(this));
        testFuzz_Mint(amount);
        // address(this) approves randomCaller to spend amount Honey.
        honey.approve(spender, amount);
        vm.expectEmit();
        emit ERC20.Transfer(address(this), to, amount);
        vm.prank(spender);
        assertTrue(honey.transferFrom(address(this), to, amount));
        assertEq(honey.totalSupply(), amount);
        assertEq(honey.balanceOf(address(this)), 0);
        assertEq(honey.balanceOf(to), amount);
    }

    function test_Permit() public {
        _TestTemps memory t = _testTemps();
        t.deadline = block.timestamp;

        _signPermit(t);

        _expectPermitEmitApproval(t);
        _permit(t);

        _checkAllowanceAndNonce(t);
    }

    function test_Permit_BadNonceReverts() public {
        _TestTemps memory t = _testTemps();
        if (t.deadline < block.timestamp) t.deadline = block.timestamp;
        while (t.nonce == 0) t.nonce = _random();

        _signPermit(t);

        vm.expectRevert(ERC20.InvalidPermit.selector);
        _permit(t);
    }

    function test_Permit_BadDeadlineReverts() public {
        _TestTemps memory t = _testTemps();
        if (t.deadline == type(uint256).max) t.deadline--;
        if (t.deadline < block.timestamp) t.deadline = block.timestamp;

        _signPermit(t);

        vm.expectRevert(ERC20.InvalidPermit.selector);
        t.deadline += 1;
        _permit(t);
    }

    function test_Permit_PastDeadlineReverts() public {
        _TestTemps memory t = _testTemps();
        t.deadline = _bound(t.deadline, 0, block.timestamp - 1);

        _signPermit(t);

        vm.expectRevert(ERC20.PermitExpired.selector);
        _permit(t);
    }

    function test_Permit_ReplayReverts() public {
        _TestTemps memory t = _testTemps();
        if (t.deadline < block.timestamp) t.deadline = block.timestamp;

        _signPermit(t);

        _expectPermitEmitApproval(t);
        _permit(t);
        vm.expectRevert(ERC20.InvalidPermit.selector);
        _permit(t);
    }

    function test_UpgradeTo_FailIfNotOwner() public {
        testFuzz_UpgradeTo_FailsIfNotOwner(address(this));
    }

    function testFuzz_UpgradeTo_FailsIfNotOwner(address caller) public {
        address newHoneyImpl = address(new Honey());
        vm.assume(caller != governance);
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, DEFAULT_ADMIN_ROLE
            )
        );
        honey.upgradeToAndCall(newHoneyImpl, bytes(""));
    }

    function test_UpgradeTo() public {
        assertEq(honey.name(), "Honey");
        assertEq(honey.symbol(), "HONEY");

        address mockHoneyOwner = address(0x3);
        vm.startPrank(mockHoneyOwner);
        MockHoney mockHoneyImpl = new MockHoney();
        mockHoneyImpl.initialize();
        vm.stopPrank();
        vm.expectEmit();
        emit ERC1967Utils.Upgraded(address(mockHoneyImpl));
        // Only DEFAULT_ADMIN_ROLE of Honey can upgrade it.
        vm.prank(governance);
        honey.upgradeToAndCall(address(mockHoneyImpl), bytes(""));
        assertEq(honey.name(), "MockHoney");
        assertEq(honey.symbol(), "MOCK_HONEY");
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   INTERNAL HELPER FUNCTIONS                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _testTemps() internal returns (_TestTemps memory t) {
        (t.owner, t.privateKey) = _randomSigner();
        t.to = _randomNonZeroAddress();
        t.amount = _random();
        t.deadline = _random();
    }

    function _checkAllowanceAndNonce(_TestTemps memory t) internal {
        assertEq(honey.allowance(t.owner, t.to), t.amount);
        assertEq(honey.nonces(t.owner), t.nonce + 1);
    }

    function _signPermit(_TestTemps memory t) internal view {
        bytes32 innerHash = keccak256(abi.encode(PERMIT_TYPEHASH, t.owner, t.to, t.amount, t.nonce, t.deadline));
        bytes32 domainSeparator = honey.DOMAIN_SEPARATOR();
        bytes32 outerHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, innerHash));
        (t.v, t.r, t.s) = vm.sign(t.privateKey, outerHash);
    }

    function _expectPermitEmitApproval(_TestTemps memory t) internal {
        vm.expectEmit(true, true, true, true);
        emit ERC20.Approval(t.owner, t.to, t.amount);
    }

    function _permit(_TestTemps memory t) internal {
        address token_ = address(honey);
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(sub(t, 0x20))
            mstore(sub(t, 0x20), 0xd505accf)
            let success := call(gas(), token_, 0, sub(t, 0x04), 0xe4, 0x00, 0x00)
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
            mstore(sub(t, 0x20), m)
        }
    }
}
