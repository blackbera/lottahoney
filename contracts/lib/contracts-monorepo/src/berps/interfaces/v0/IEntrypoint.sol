// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IPyth } from "@pythnetwork/IPyth.sol";

import "../utils/IDelegatable.sol";

import "./IOrders.sol";
import "./ISettlement.sol";

interface IEntrypoint is IDelegatable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event Done(bool done);
    event Paused(bool paused);
    event PythUpdated(IPyth pyth);
    event StaleToleranceUpdated(uint64 staleTolerance);
    event MaxPosHoneyUpdated(uint256 newValue);

    /// @notice Emitted when a limit order is opened by a trader
    event OpenLimitPlaced(IOrders.OpenLimitOrder order);

    /// @notice Emitted when a limit order is updated by a trader
    event OpenLimitUpdated(uint256 index, uint256 pairIndex, bool buy, int64 newPrice, int64 newTp, int64 newSl);

    /// @notice Emitted when a limit order is canceled by a trader
    event OpenLimitCanceled(uint256 index, uint256 pairIndex);

    /// @notice Emitted when a trader updates the TP of an open market position
    event TpUpdated(uint256 index, uint256 pairIndex, bool buy, int64 newTp);

    /// @notice Emitted when a trader updates the SL of an open market position
    event SlUpdated(uint256 index, uint256 pairIndex, bool buy, int64 newSl);

    /// @notice Emitted when a trade or open limit order that does not exist is tried to execute.
    event InvalidLimitExecution(uint256 index);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        TRADING VIEWS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function maxPosHoney() external view returns (uint256);

    function isPaused() external view returns (bool);

    function isDone() external view returns (bool);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     TRADING OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Only callable via a ERC1967 Proxy contract.
    function initialize(
        address _pyth,
        address _orders,
        address _feesMarkets,
        address _feesAccrued,
        uint64 _staleTolerance,
        uint256 _maxPosHoney
    )
        external;

    function openTrade(
        IOrders.Trade memory t,
        ISettlement.TradeType orderType,
        int64 slippageP, // for market orders only
        bytes[] calldata priceUpdateData
    )
        external
        payable;

    function closeTradeMarket(uint256 index, bytes[] calldata priceUpdateData) external payable;

    function updateOpenLimitOrder(
        uint256 index,
        int64 newPrice, // PRECISION
        int64 tp,
        int64 sl,
        bytes[] calldata priceUpdateData
    )
        external
        payable;

    function cancelOpenLimitOrder(uint256 index) external;

    function updateTp(uint256 index, int64 newTp) external;

    function updateSl(uint256 index, int64 newSl, bytes[] calldata priceUpdateData) external payable;

    /// @notice executeLimitOrder is used to open a limit order into a market position or close a market order via
    /// take profit, stop loss, or liquidation
    /// @notice limit fees (rates are determined by the pair) accrue to the executor, or `msg.sender`
    /// @param index is the index of the limit order OR the trade
    /// @dev calling this function through a delegated action will reward only the `msg.sender`,
    /// NOT the delegate (`senderOverride`)
    function executeLimitOrder(uint256 index, bytes[] calldata priceUpdateData) external payable;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            PYTH                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Will revert to PythErrors.StalePrice() if a provided price update is older than this value.
    /// @dev More info: https://docs.pyth.network/price-feeds/best-practices#price-availability
    function staleTolerance() external view returns (uint64);

    function pyth() external view returns (IPyth);
}
