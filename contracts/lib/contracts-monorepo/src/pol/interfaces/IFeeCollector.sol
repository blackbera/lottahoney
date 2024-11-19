// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IPOLErrors } from "./IPOLErrors.sol";

interface IFeeCollector is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emit when the payout token is updated.
    event PayoutTokenSet(address indexed oldPayoutToken, address indexed newPayoutToken);

    /// @notice Emitted when the admin updates the payout amount.
    event PayoutAmountSet(uint256 indexed oldPayoutAmount, uint256 indexed newPayoutAmount);

    /// @notice Emitted when the dapp fees are claimed.
    /// @param caller Caller of the `claimFees` function.
    /// @param recipient The address to which collected dapp fees will be transferred.
    event FeesClaimed(address indexed caller, address indexed recipient);

    /// @notice Emitted when the `PayoutToken` is donated.
    /// @param caller Caller of the `donate` function.
    /// @param amount The amount of payout token that is transfered.
    event PayoutDonated(address indexed caller, uint256 amount);

    /// @notice Emitted when the fees are claimed.
    /// @param caller Caller of the `claimFees` function.
    /// @param recipient The address to which collected dapp fees will be transferred.
    /// @param feeToken The address of the fee token to collect.
    /// @param amount The amount of fee token to transfer.
    event FeesClaimed(address indexed caller, address indexed recipient, address indexed feeToken, uint256 amount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Set the ERC-20 token which must be used to pay for fees when claiming dapp fees.
    /// @param _newPayoutToken The address of the new payout token.
    function setPayoutToken(address _newPayoutToken) external;

    /// @notice Update the payout amount to a new value. Must be called by admin.
    /// @param _newPayoutAmount The value that will be the new payout amount.
    function setPayoutAmount(uint256 _newPayoutAmount) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The ERC-20 token which must be used to pay for fees when claiming dapp fees.
    function payoutToken() external view returns (address);

    /// @notice The amount of payout token that is required to claim dapp fees of a particular token.
    /// @dev This works as first come first serve basis. whoever pays this much amount of the payout amount first will
    /// get the fees.
    function payoutAmount() external view returns (uint256);

    /// @notice The contract that receives the payout and is notified via method call, when dapp fees are claimed.
    function rewardReceiver() external view returns (address);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  STATE MUTATING FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Claim collected dapp fees and transfer them to the recipient.
    /// @param recipient The address to which collected dapp fees will be transferred.
    /// @param feeTokens The addresses of the fee token to collect to the recipient.
    /// @dev Caller need to pay the PAYMENT_AMOUNT of PAYOUT_TOKEN tokens.
    function claimFees(address recipient, address[] calldata feeTokens) external;

    /// @notice directly sends dapp fees from msg.sender to the BGTStaker reward receiver.
    /// @dev The dapp fee ERC20 token MUST be the payoutToken.
    /// @dev The amount must be at least payoutAmount to notify the reward receiver.
    /// @param amount the amount of fee token to directly send to the reward receiver.
    function donate(uint256 amount) external;

    /// @notice Allows the owner to pause the collector.
    function pause() external;

    /// @notice Allows the owner to unpause the collector.
    function unpause() external;
}