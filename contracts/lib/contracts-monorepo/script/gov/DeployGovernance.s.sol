// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { Script, console2 } from "forge-std/Script.sol";

import { TimelockControllerUpgradeable } from "@openzeppelin-gov/TimelockControllerUpgradeable.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import { Create2Deployer } from "src/base/Create2Deployer.sol";
import { BerachainGovernance, InitialGovernorParameters } from "src/gov/BerachainGovernance.sol";
import { TimeLock } from "src/gov/TimeLock.sol";

contract DeployGovernance is Script, Create2Deployer {
    /// @notice The hardcoded address of BGT
    address internal constant GOV_TOKEN = 0xbDa130737BDd9618301681329bF2e46A016ff9Ad;
    /// @notice Minimum amount of delegated governance tokens for proposal creation
    uint256 internal constant GOV_PROPOSAL_THRESHOLD = 1000e18;
    /// @notice Time delay between proposal creation and voting period
    uint256 internal constant GOV_VOTING_DELAY = 0;
    /// @notice Time duration of the voting period
    uint256 internal constant GOV_VOTING_PERIOD = 7 days;
    /// @notice Numerator of the needed quorum percentage
    uint256 internal constant GOV_QUORUM_NUMERATOR = 10;
    /// @notice Time duration of the enforced time-lock
    uint256 internal constant TIMELOCK_MIN_DELAY = 2 days;
    /// @notice The average block time in milli-seconds
    uint256 internal constant AVG_BLOCK_TIME_MS = 1900;
    /// @notice The expected EIP-6372 clock mode of the governance token upon which this script is based
    string internal constant GOV_TOKEN_CLOCK_MODE = "mode=blocknumber&from=default";
    /// @notice The guardian multi-sig, if any
    address internal constant GOV_GUARDIAN = address(0);
    /// @notice The CREATE2 salts to use for address consistency
    uint256 internal constant GOV_CREATE2_NONCE = 0;
    uint256 internal constant TIMELOCK_CREATE2_NONCE = 0;

    function run() public {
        vm.startBroadcast();

        BerachainGovernance governance =
            BerachainGovernance(deploy(type(BerachainGovernance).creationCode, GOV_CREATE2_NONCE));
        console2.log("BerachainGovernance deployed at:", address(governance));

        TimeLock timelock = TimeLock(deploy(type(TimeLock).creationCode, TIMELOCK_CREATE2_NONCE));
        console2.log("TimeLock deployed at:", address(timelock));

        address[] memory enabledContracts = new address[](1);
        enabledContracts[0] = address(governance);
        // NOTE: temprorary provide the admin role to msg.sender in order to set the guardian.
        timelock.initialize(TIMELOCK_MIN_DELAY, enabledContracts, enabledContracts, msg.sender);
        if (GOV_GUARDIAN != address(0)) {
            timelock.grantRole(timelock.CANCELLER_ROLE(), GOV_GUARDIAN);
        }
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), msg.sender);
        console2.log("TimeLock initialized");

        InitialGovernorParameters memory params = InitialGovernorParameters({
            proposalThreshold: GOV_PROPOSAL_THRESHOLD,
            quorumNumeratorValue: GOV_QUORUM_NUMERATOR,
            votingDelay: uint48(timeToBlocks(GOV_VOTING_DELAY)),
            votingPeriod: uint32(timeToBlocks(GOV_VOTING_PERIOD))
        });

        governance.initialize(IVotes(GOV_TOKEN), TimelockControllerUpgradeable(timelock), params);
        console2.log("BerachainGovernance initialized");

        // As this scripts uses `timeToBlocks`, check that the clock mode is the expected one:
        require(
            keccak256(bytes(governance.CLOCK_MODE())) == keccak256(bytes(GOV_TOKEN_CLOCK_MODE)),
            "Unexpected EIP-6372 clock mode"
        );

        console2.log("Please provide the needed roles/permissions to the TimeLock contract");
        vm.stopBroadcast();
    }

    /**
     * @notice Deploy a proxied contract with CREATE2.
     * @param creationCode The type(Contract).creationCode value.
     * @param salt The salt value.
     * @return proxy The address of the deployed proxy.
     */
    function deploy(bytes memory creationCode, uint256 salt) internal returns (address payable proxy) {
        address impl = deployWithCreate2(salt, creationCode);
        proxy = payable(deployProxyWithCreate2(impl, salt));
    }

    /**
     * @notice Approximate the number of blocks over a period of time.
     * @param time The period of time in seconds.
     * @return blocks The expected number of blocks.
     * @dev It requires a prior knowledge of the average block time, which may be unknown on genesis.
     */
    function timeToBlocks(uint256 time) internal pure returns (uint256 blocks) {
        blocks = time * 1000 / AVG_BLOCK_TIME_MS;

        // Fallback for safety:
        if (blocks == 0) {
            blocks = 1;
        }
    }
}
