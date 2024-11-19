// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Utils } from "../libraries/Utils.sol";
import { IFeeCollector } from "./interfaces/IFeeCollector.sol";
import { BGTStaker } from "./BGTStaker.sol";

/**
 * @title FeeCollector
 * @author Berachain Team
 * @notice The Fee Collector contract is responsible for collecting fees from Berachain Dapps and
 * auctioning them for a Payout token which then is distributed among the BGT stakers.
 * @dev This contract is inspired by the Uniswap V3 Factory Owner contract.
 * https://github.com/uniswapfoundation/UniStaker/blob/main/src/V3FactoryOwner.sol
 */
contract FeeCollector is IFeeCollector, PausableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeTransferLib for address;
    using Utils for bytes4;

    /// @notice The MANAGER role.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @inheritdoc IFeeCollector
    address public payoutToken;

    /// @inheritdoc IFeeCollector
    uint256 public payoutAmount;

    /// @inheritdoc IFeeCollector
    address public rewardReceiver;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address governance,
        address _payoutToken,
        address _rewardReceiver,
        uint256 _payoutAmount
    )
        external
        initializer
    {
        if (governance == address(0) || _payoutToken == address(0) || _rewardReceiver == address(0)) {
            ZeroAddress.selector.revertWith();
        }
        if (_payoutAmount == 0) PayoutAmountIsZero.selector.revertWith();

        _grantRole(DEFAULT_ADMIN_ROLE, governance);

        payoutToken = _payoutToken;
        payoutAmount = _payoutAmount;
        rewardReceiver = _rewardReceiver;

        emit PayoutAmountSet(0, _payoutAmount);
        emit PayoutTokenSet(address(0), _payoutToken);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    /// @inheritdoc IFeeCollector
    function setPayoutAmount(uint256 _newPayoutAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newPayoutAmount == 0) PayoutAmountIsZero.selector.revertWith();
        emit PayoutAmountSet(payoutAmount, _newPayoutAmount);
        payoutAmount = _newPayoutAmount;
    }

    /// @inheritdoc IFeeCollector
    function setPayoutToken(address _newPayoutToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newPayoutToken == address(0)) ZeroAddress.selector.revertWith();
        emit PayoutTokenSet(payoutToken, _newPayoutToken);
        payoutToken = _newPayoutToken;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       WRITE FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IFeeCollector
    function claimFees(address _recipient, address[] calldata _feeTokens) external whenNotPaused {
        // Transfer the payout amount of the payout token to the BGTStaker contract from msg.sender.
        payoutToken.safeTransferFrom(msg.sender, rewardReceiver, payoutAmount);
        // Notify that the reward amount has been updated.
        BGTStaker(rewardReceiver).notifyRewardAmount(payoutAmount);
        // From all the specified fee tokens, transfer them to the recipient.
        for (uint256 i; i < _feeTokens.length;) {
            address feeToken = _feeTokens[i];
            uint256 feeTokenAmountToTransfer = feeToken.balanceOf(address(this));
            feeToken.safeTransfer(_recipient, feeTokenAmountToTransfer);
            emit FeesClaimed(msg.sender, _recipient, feeToken, feeTokenAmountToTransfer);
            unchecked {
                ++i;
            }
        }
        emit FeesClaimed(msg.sender, _recipient);
    }

    /// @inheritdoc IFeeCollector
    function donate(uint256 amount) external {
        // donate amount should be at least payoutAmount to notify the reward receiver.
        if (amount < payoutAmount) DonateAmountLessThanPayoutAmount.selector.revertWith();

        // Directly send the fees to the reward receiver.
        payoutToken.safeTransferFrom(msg.sender, rewardReceiver, amount);
        BGTStaker(rewardReceiver).notifyRewardAmount(amount);

        emit PayoutDonated(msg.sender, amount);
    }

    /// @inheritdoc IFeeCollector
    function pause() external onlyRole(MANAGER_ROLE) {
        _pause();
    }

    /// @inheritdoc IFeeCollector
    function unpause() external onlyRole(MANAGER_ROLE) {
        _unpause();
    }
}
