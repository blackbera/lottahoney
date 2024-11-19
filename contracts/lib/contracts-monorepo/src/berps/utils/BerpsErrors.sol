// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library BerpsErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Inputs / Authority                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // Signature: 0x5863f789
    error WrongParams();
    /// Signature: 0x82b42900
    error Unauthorized();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      Pyth Validation                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // Pyth prices must have negative expo values.
    //
    // More info: https://docs.pyth.network/price-feeds/best-practices#fixed-point-numeric-representation
    // Signature: 0x39c733d8
    error InvalidExpo(int32 pythExpo);
    // The confidence interval is wider than the desired threshold and the protocol is not using
    // confidence ranges.
    //
    // More info: https://docs.pyth.network/price-feeds/best-practices#confidence-intervals
    // Signature: 0xe7cd821c
    error InvalidConfidence(uint256 invalidConfP);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    Entrypoint Validation                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // Signature: 0x9f9fb434
    error Done();
    // Signature: 0x9e87fac8
    error Paused();
    // Signature: 0xa3b36525
    error NoTrade();
    // Signature: 0xe6803dc4
    error NoLimit();
    // Signature: 0x3577cd46
    error WrongLimitPrice();
    // Signature: 0x7f527065
    error WrongTp();
    // Signature: 0x62dd5ee3
    error WrongSl();
    // Signature: 0x506bf1a8
    error InTimeout();
    // Signature: 0xfb30d03a
    error PriceImpactTooHigh();
    // Signature: 0x23d16341
    error PairNotListed();
    // Signature: 0xa38355c0
    error MaxTradesPerPair();
    // Signature: 0xb4503281
    error AboveMaxPos();
    // Signature: 0x7061e4f8
    error AboveMaxGroupCollateral();
    // Signature: 0x7061fe95
    error LeverageIncorrect();
    // Signature: 0x8d5543b1
    error BelowMinPos();
    // Signature: 0x742087f6
    error PriceNotHit();
    // Signature: 0x8199f5f3
    error SlippageExceeded();
    // Signature: 0x40305e8d
    error TpReached();
    // Signature: 0xfa0789e0
    error SlReached();
    // Signature: 0x0c26d69e
    error PastExposureLimits();
    // Signature: 0x0b5f6bf0
    error MarketClosed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                             Vault                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // Signature: 0xe528e11e
    error PriceZero();
    // Signature: 0x423023f1
    error PendingWithdrawal();
    // Signature: 0x4e00e1c0
    error MoreThanWithdrawAmount();
    // Signature: 0x3786fdd4
    error NotEnoughAssets();
    // Signature: 0xb2ac7c0c
    error MaxDailyPnL();
    // ERC4626 deposit/mint more than max
    // Signature: 0x3b8698ab
    error MaxDeposit();
    // ERC4626 withdraw/redeem more than max
    // Signature: 0x3ae3d0cf
    error MaxWithdraw();
    // Signature: 0xf4d678b8
    error InsufficientBalance();
    // Signature: 0x085de625
    error TooEarly();
    // Signature: 0xae8accbc
    error WrongCollatPForRecapital(uint256 _collatP);
    // Signature: 0x0ad1e31b
    error AboveMax();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           Referrals                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // Signature: 0x61104228
    error InvalidReferrer();
    // Signature: 0x7aabdfe3
    error AlreadyReferred();
    // Signature: 0x8f6f8611
    error ReferralCycle();
}
