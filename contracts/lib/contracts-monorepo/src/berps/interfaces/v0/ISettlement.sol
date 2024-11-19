// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IVault, IReferrals, IOrders } from "./IOrders.sol";

interface ISettlement {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            ENUMS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    enum TradeType {
        MARKET,
        LIMIT
    }

    enum CancelReason {
        NONE,
        PAUSED,
        SLIPPAGE,
        TP_REACHED,
        SL_REACHED,
        EXPOSURE_LIMITS,
        PRICE_IMPACT,
        MAX_LEVERAGE,
        NO_TRADE,
        IN_TIMEOUT,
        NOT_HIT
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            STRUCTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Block numbers of when each of these were last updated for particular trade or limit order.
    struct LastUpdated {
        uint64 tp;
        uint64 sl;
        uint64 limit;
        uint64 created;
    }

    // Useful to avoid stack too deep errors
    struct Values {
        uint256 posHoney;
        uint256 levPosHoney;
        int64 tokenPriceHoney;
        int256 profitP;
        int64 price;
        int64 liqPrice;
        IOrders.LimitOrder orderType;
        uint256 reward1;
        uint256 reward2;
        uint256 reward3;
        uint256 honeySentToTrader;
    }

    /// @notice Contains all fees associated with closing a market position
    /// @dev all fees are in HONEY, precision of 1e18
    struct ClosingFees {
        uint256 borrowFee;
        uint256 closeFee;
        uint256 rolloverFee;
        int256 fundingFee;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a market position is opened by a trader
    event MarketOpened(IOrders.Trade t, int64 priceImpactP, uint256 openFee);

    /// @notice Emitted when a market position is closed by a trader
    event MarketClosed(IOrders.Trade t, int64 closePrice, int256 percentProfit, int256 pnl, ClosingFees fees);

    /// @notice Emitted when a limit order is canceled since the SL was reached before a market position could be
    /// opened.
    event OpenLimitSlCanceled(uint256 limitIndex, uint256 pairIndex, int64 currPrice, int64 sl);

    /// @notice Emitted when a limit order is opened into a market position
    event LimitOpenExecuted(
        address indexed executor, uint256 limitIndex, IOrders.Trade t, int64 priceImpactP, uint256 openFee
    );

    /// @notice Emitted when a limit execution is unable to open a limit order into a market position
    event LimitOpenCanceled(
        address indexed executor,
        uint256 limitIndex,
        CancelReason cancelReason,
        int64 currPrice,
        int64 minExecPrice,
        int64 maxExecPrice
    );

    /// @notice Emitted when a market position is closed by a limit execution
    /// @param closeType will be one of TP, SL, or LIQ
    event LimitCloseExecuted(
        address indexed executor,
        IOrders.Trade t,
        IOrders.LimitOrder closeType,
        int64 closePrice,
        int256 percentProfit,
        int256 pnl,
        ClosingFees fees
    );

    /// @notice Emitted when a market position is unable to be closed by a limit execution
    event LimitCloseCanceled(
        address indexed executor,
        uint256 tradeIndex,
        CancelReason cancelReason,
        int64 currPrice,
        int64 tp,
        int64 sl,
        int64 liq
    );

    /// @notice Emitted when a trader updates the stop loss on an open market position
    event SlUpdated(
        uint256 indexed index, uint256 pairIndex, bool buy, int64 newSl, uint256 initialPosToken, uint256 posSizeHoney
    );

    event CanExecuteTimeoutUpdated(uint64 newValue);
    event PairMaxLeverageUpdated(uint256 indexed pairIndex, uint256 maxLeverage);
    event UpdateSlFeePUpdated(uint256 newValue);
    event LiqFeePUpdated(uint256 newValue);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                             VIEWS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function vault() external view returns (IVault);

    function referrals() external view returns (IReferrals);

    function canExecuteTimeout() external view returns (uint64);

    function updateSlFeeP() external view returns (uint256);

    function liqFeeP() external view returns (uint256);

    function tradeLastUpdated(uint256) external view returns (LastUpdated memory);

    function pairMaxLeverage(uint256) external view returns (uint256);

    function getAllPairsMaxLeverage() external view returns (uint256[] memory);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     TRADING OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Only callable via a ERC1967 Proxy contract.
    function initialize(
        address _orders,
        address _feesMarkets,
        address _referrals,
        address _feesAccrued,
        address _vault,
        address _honey,
        uint64 _canExecuteTimeout,
        uint256 _updateSlFeeP,
        uint256 _liqFeeP
    )
        external;

    /// @dev Should only be used by the entrypoint contract for canceled limit orders.
    function removeLimitLastUpdated(uint256) external;

    /// @notice Set trade last updated details externally, for both open limit orders and open trades.
    function setTradeLastUpdated(uint256, LastUpdated memory) external;

    function openTradeMarketCallback(int64, int64, IOrders.Trade memory, int64, int64) external;

    function closeTradeMarketCallback(int64, uint256) external;

    function executeLimitOpenOrderCallback(int64, int64, IOrders.OpenLimitOrder memory, address, bool) external;

    function executeLimitCloseOrderCallback(int64, uint256, address) external;

    function updateSlCallback(int64, int64, uint256, int64) external;
}
