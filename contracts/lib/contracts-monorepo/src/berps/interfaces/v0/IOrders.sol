// SPDX-License-Identifier: MIT

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";
import { IMarkets } from "./IMarkets.sol";
import { IReferrals } from "./IReferrals.sol";

pragma solidity ^0.8.21;

interface IOrders {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            ENUMS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    enum LimitOrder {
        TP,
        SL,
        LIQ,
        OPEN
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            STRUCTS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct Trade {
        address trader;
        uint256 pairIndex;
        uint256 index; // don't need, will auto-fill
        uint256 initialPosToken; // 1e18
        uint256 positionSizeHoney; // 1e18
        int64 openPrice; // PRECISION == 1e10
        bool buy;
        uint256 leverage;
        int64 tp; // PRECISION
        int64 sl; // PRECISION
    }

    struct TradeInfo {
        int64 tokenPriceHoney; // PRECISION
        uint256 openInterestHoney; // positionSize * leverage (1e18)
    }

    struct OpenLimitOrder {
        address trader;
        uint256 pairIndex;
        uint256 index;
        uint256 positionSize; // 1e18 (HONEY)
        bool buy;
        uint256 leverage;
        int64 tp; // PRECISION (%)
        int64 sl; // PRECISION (%)
        int64 minPrice; // PRECISION
        int64 maxPrice; // PRECISION
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event TradingContractAdded(address a);
    event TradingContractRemoved(address a);
    event AddressUpdated(string name, address a);
    event NumberUpdated(string name, uint256 value);
    event NumberUpdatedPair(string name, uint256 pairIndex, uint256 value);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                             VIEWS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function gov() external view returns (address);

    function honey() external view returns (address);

    function vault() external view returns (IVault);

    function referrals() external view returns (IReferrals);

    function entrypoint() external view returns (address);

    function settlement() external view returns (address);

    function markets() external view returns (IMarkets);

    function globalIndex() external view returns (uint256);

    function maxTradesPerPair() external view returns (uint256);

    function openInterestHoney(uint256, uint256) external view returns (uint256);

    function getOpenLimitOrder(uint256) external view returns (OpenLimitOrder memory);

    function getOpenLimitOrdersCount(address, uint256) external view returns (uint256);

    function getOpenLimitOrders(uint256, uint256) external view returns (OpenLimitOrder[] memory);

    function getOpenTrade(uint256) external view returns (Trade memory);

    function getOpenTradeInfo(uint256) external view returns (TradeInfo memory);

    function getOpenTradesCount(address, uint256) external view returns (uint256);

    function getOpenTrades(uint256 offset, uint256 count) external view returns (Trade[] memory);

    function getOpenTradeInfos(uint256 offset, uint256 count) external view returns (TradeInfo[] memory);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     TRADING OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Only callable via a ERC1967 Proxy contract.
    function initialize(
        address _honey,
        address _gov,
        address _markets,
        address _vault,
        address _entrypoint,
        address _settlement,
        address _referrals
    )
        external;

    function transferHoney(address, address, uint256) external;

    function unregisterTrade(uint256) external;

    function unregisterOpenLimitOrder(uint256) external;

    function updateSl(uint256, int64) external;

    function updateTp(uint256, int64) external;

    function storeOpenLimitOrder(OpenLimitOrder memory) external;

    function updateOpenLimitOrder(OpenLimitOrder calldata) external;

    function updateTrade(Trade memory) external;

    function handleDevGovFees(uint256, uint256) external returns (uint256);

    function storeTrade(Trade memory, TradeInfo memory) external;
}
