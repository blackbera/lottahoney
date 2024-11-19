// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { Utils } from "../../../libraries/Utils.sol";

import { BerpsErrors } from "../../utils/BerpsErrors.sol";
import { StorageUtils } from "../../utils/StorageUtils.sol";

import "../../interfaces/v0/IOrders.sol";

/// @notice Orders contains all on-chain open trades and limit orders.
contract Orders is UUPSUpgradeable, IOrders {
    using SafeTransferLib for address;
    using StorageUtils for address;
    using Utils for bytes4;

    // Constants
    uint256 public constant PRECISION = 1e10;
    address public override honey;

    // Contracts (constant)
    IMarkets public override markets;
    address public override entrypoint;
    address public override settlement;

    // Contracts (updatable)
    IReferrals public override referrals;
    IVault public override vault;

    // Entrypoint variables
    uint256 public override maxTradesPerPair;
    mapping(bytes32 traderCountKey => uint256) private openTradesCount;
    mapping(bytes32 traderCountKey => uint256) private openLimitOrdersCount;

    // Gov address (updatable)
    address public override gov;

    // Trades mappings
    mapping(uint256 tradeIndex => uint256) private openTradeIds;
    Trade[] private openTrades;
    TradeInfo[] private openTradeInfos;

    // Limit orders mappings
    mapping(uint256 limitIndex => uint256) private openLimitOrderIds;
    OpenLimitOrder[] private openLimitOrders;

    // Global, always incrementing, unique index used for all (historical included) trades / limit orders
    uint256 public override globalIndex;

    // Current and max open interests for each pair
    mapping(uint256 => uint256[3]) public override openInterestHoney; // 1e18 [long, short, max]

    // List of allowed contracts that can update storage
    mapping(address => bool) public isTradingContract;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGov { }

    /// @inheritdoc IOrders
    function initialize(
        address _honey,
        address _gov,
        address _markets,
        address _vault,
        address _entrypoint,
        address _settlement,
        address _referrals
    )
        external
        initializer
    {
        if (
            _honey == address(0) || _gov == address(0) || _markets == address(0) || _vault == address(0)
                || _entrypoint == address(0) || _settlement == address(0) || _referrals == address(0)
        ) BerpsErrors.WrongParams.selector.revertWith();

        gov = _gov;
        honey = _honey;
        vault = IVault(_vault);
        markets = IMarkets(_markets);

        entrypoint = _entrypoint;
        isTradingContract[_entrypoint] = true;
        emit TradingContractAdded(_entrypoint);

        settlement = _settlement;
        isTradingContract[_settlement] = true;
        emit TradingContractAdded(_settlement);

        referrals = IReferrals(_referrals);
        isTradingContract[_referrals] = true;
        emit TradingContractAdded(_referrals);

        // approve all contracts to use honey from storage
        honey.safeApprove(_vault, type(uint256).max);
        honey.safeApprove(_entrypoint, type(uint256).max);
        honey.safeApprove(_settlement, type(uint256).max);

        // defaults
        maxTradesPerPair = 3;

        // Skip the 0th element in the arrays to make the ids 1-indexed.
        openLimitOrders.push();
        openTrades.push();
        openTradeInfos.push();
    }

    // Modifiers
    modifier onlyGov() {
        require(msg.sender == gov);
        _;
    }

    modifier onlyTrading() {
        if (!isTradingContract[msg.sender]) BerpsErrors.Unauthorized.selector.revertWith();
        _;
    }

    // Manage addresses
    function setGov(address _gov) external onlyGov {
        require(_gov != address(0));
        gov = _gov;
        emit AddressUpdated("gov", _gov);
    }

    function addTradingContract(address _trading) external onlyGov {
        require(_trading != address(0) && !isTradingContract[_trading]);
        isTradingContract[_trading] = true;
        emit TradingContractAdded(_trading);
    }

    function removeTradingContract(address _trading) external onlyGov {
        require(_trading != address(0) && isTradingContract[_trading]);
        isTradingContract[_trading] = false;
        emit TradingContractRemoved(_trading);
    }

    // Manage trading variables
    function setMaxTradesPerPair(uint256 _maxTradesPerPair) external onlyGov {
        require(_maxTradesPerPair > 0);
        maxTradesPerPair = _maxTradesPerPair;
        emit NumberUpdated("maxTradesPerPair", _maxTradesPerPair);
    }

    function setMaxOpenInterestHoney(uint256 _pairIndex, uint256 _newMaxOpenInterest) external onlyGov {
        // Can set max open interest to 0 to pause trading on this pair only
        openInterestHoney[_pairIndex][2] = _newMaxOpenInterest;
        emit NumberUpdatedPair("maxOpenInterestHoney", _pairIndex, _newMaxOpenInterest);
    }

    // Manage stored trades
    function storeTrade(Trade memory t, TradeInfo memory i) external override onlyTrading {
        t.index = globalIndex++;
        openTradeIds[t.index] = openTrades.length;
        openTrades.push(t);
        openTradeInfos.push(i);
        ++openTradesCount[t.trader.traderCountKeyFor(t.pairIndex)];

        updateOpenInterestHoney(t.pairIndex, i.openInterestHoney, true, t.buy);
    }

    function unregisterTrade(uint256 removeIndex) external override onlyTrading {
        // Get the trade id for the removal trade.
        uint256 id = openTradeIds[removeIndex];
        Trade memory removeT = openTrades[id];
        if (removeT.leverage == 0) return;

        // Update the trader's count for removing this trade.
        --openTradesCount[removeT.trader.traderCountKeyFor(removeT.pairIndex)];

        // Update the open interest for this pair for removing this trade.
        TradeInfo memory removeI = openTradeInfos[id];
        updateOpenInterestHoney(removeT.pairIndex, removeI.openInterestHoney, false, removeT.buy);

        // If the removal trade is not last in the array, swap the last trade with the removal trade.
        // This allows us to safely pop from the end of the array.
        uint256 lastId = openTrades.length - 1;
        if (id != lastId) {
            // Get the last trade in the openTrades array.
            Trade memory replaceT = openTrades[lastId];

            // The last trade is "replacing" the id of the removal trade.
            openTrades[id] = replaceT;
            openTradeInfos[id] = openTradeInfos[lastId];

            // Update the mapping for the replaced trade to now point to the replacement id.
            openTradeIds[replaceT.index] = id;
        }

        // Remove the entry in mapping for the removal trade.
        delete openTradeIds[removeIndex];

        // Pop the last element (removal trade) in the arrays.
        openTrades.pop();
        openTradeInfos.pop();
    }

    // Manage open interest
    function updateOpenInterestHoney(
        uint256 _pairIndex,
        uint256 _leveragedPosHoney,
        bool _open,
        bool _long
    )
        internal
    {
        uint256 index = _long ? 0 : 1;
        uint256[3] storage o = openInterestHoney[_pairIndex];
        o[index] = _open ? o[index] + _leveragedPosHoney : o[index] - _leveragedPosHoney;
    }

    // Manage open limit orders
    function storeOpenLimitOrder(OpenLimitOrder memory o) external override onlyTrading {
        o.index = globalIndex++;
        openLimitOrderIds[o.index] = openLimitOrders.length;
        openLimitOrders.push(o);
        ++openLimitOrdersCount[o.trader.traderCountKeyFor(o.pairIndex)];
    }

    function updateOpenLimitOrder(OpenLimitOrder calldata _o) external override onlyTrading {
        OpenLimitOrder storage o = openLimitOrders[openLimitOrderIds[_o.index]];
        if (o.leverage == 0) return;
        o.positionSize = _o.positionSize;
        o.buy = _o.buy;
        o.leverage = _o.leverage;
        o.tp = _o.tp;
        o.sl = _o.sl;
        o.minPrice = _o.minPrice;
        o.maxPrice = _o.maxPrice;
    }

    function unregisterOpenLimitOrder(uint256 removeIndex) external override onlyTrading {
        // Get the open limit order id for the removal order.
        uint256 id = openLimitOrderIds[removeIndex];
        OpenLimitOrder memory removeO = openLimitOrders[id];
        if (removeO.leverage == 0) return;

        // Update the trader's count for removing this open limit order.
        --openLimitOrdersCount[removeO.trader.traderCountKeyFor(removeO.pairIndex)];

        // If the removal order is not last in the array, swap the last order with the removal order.
        // This allows us to safely pop from the end of the array.
        uint256 lastId = openLimitOrders.length - 1;
        if (id != lastId) {
            // Get the last order in the openLimitOrders array.
            OpenLimitOrder memory replaceO = openLimitOrders[lastId];

            // The last order is "replacing" the id of the removal order.
            openLimitOrders[id] = replaceO;

            // Update the mapping for the replaced order to now point to the replacement id.
            openLimitOrderIds[replaceO.index] = id;
        }

        // Remove the entry in mapping for the removal order.
        delete openLimitOrderIds[removeIndex];

        // Pop the last element (removal order) in the array.
        openLimitOrders.pop();
    }

    // Manage open trade
    function updateSl(uint256 tradeIndex, int64 newSl) external override onlyTrading {
        uint256 id = openTradeIds[tradeIndex];
        Trade storage t = openTrades[id];
        if (t.leverage == 0) return;
        t.sl = newSl;
    }

    function updateTp(uint256 tradeIndex, int64 newTp) external override onlyTrading {
        uint256 id = openTradeIds[tradeIndex];
        Trade storage t = openTrades[id];
        if (t.leverage == 0) return;
        t.tp = newTp;
    }

    function updateTrade(Trade memory _t) external override onlyTrading {
        // useful when partial adding/closing
        Trade storage t = openTrades[openTradeIds[_t.index]];
        if (t.leverage == 0) return;
        t.initialPosToken = _t.initialPosToken;
        t.positionSizeHoney = _t.positionSizeHoney;
        t.openPrice = _t.openPrice;
        t.leverage = _t.leverage;
    }

    // Manage dev & gov fees
    function handleDevGovFees(
        uint256 _pairIndex,
        uint256 _leveragedPositionSize
    )
        external
        override
        onlyTrading
        returns (uint256 fee)
    {
        fee = (_leveragedPositionSize * markets.pairOpenFeeP(_pairIndex)) / PRECISION / 100;
        vault.distributeReward(fee);
    }

    function transferHoney(address _from, address _to, uint256 _amount) external override onlyTrading {
        if (_from == address(this)) {
            honey.safeTransfer(_to, _amount);
        } else {
            honey.safeTransferFrom(_from, _to, _amount);
        }
    }

    // View utils functions
    function getOpenTrade(uint256 tradeIndex) external view override returns (Trade memory trade) {
        uint256 id = openTradeIds[tradeIndex];
        if (id == 0 || id >= openTrades.length) return trade;
        trade = openTrades[id];
    }

    function getOpenTradeInfo(uint256 tradeIndex) external view override returns (TradeInfo memory tradeInfo) {
        uint256 id = openTradeIds[tradeIndex];
        if (id == 0 || id >= openTradeInfos.length) return tradeInfo;
        tradeInfo = openTradeInfos[id];
    }

    function getOpenTradesCount(address trader, uint256 pairIndex) external view override returns (uint256) {
        return openTradesCount[trader.traderCountKeyFor(pairIndex)];
    }

    function getOpenTrades(uint256 offset, uint256 count) external view override returns (Trade[] memory trades) {
        // The 0th element in the array is skipped to make the index 1-based.
        if (offset == 0) return new Trade[](0);

        // If the count requested is 0 or the offset is beyond the array length, return an empty array.
        if (count == 0 || offset >= openTrades.length) return new Trade[](0);

        // Calculate the size of the array to return: smaller of `count` or `openTrades.length - offset`.
        uint256 outputSize = (offset + count > openTrades.length) ? openTrades.length - offset : count;

        // Initialize the array of results and populate.
        trades = new Trade[](outputSize);
        unchecked {
            for (uint256 i; i < outputSize; ++i) {
                trades[i] = openTrades[offset + i];
            }
        }
    }

    function getOpenTradeInfos(
        uint256 offset,
        uint256 count
    )
        external
        view
        override
        returns (TradeInfo[] memory tradeInfos)
    {
        // The 0th element in the array is skipped to make the index 1-based.
        if (offset == 0) return new TradeInfo[](0);

        // If the count requested is 0 or the offset is beyond the array length, return an empty array.
        if (count == 0 || offset >= openTradeInfos.length) return new TradeInfo[](0);

        // Calculate the size of the array to return: smaller of `count` or `openTradeInfos.length - offset`.
        uint256 outputSize = (offset + count > openTradeInfos.length) ? openTradeInfos.length - offset : count;

        // Initialize the array of results and populate.
        tradeInfos = new TradeInfo[](outputSize);
        unchecked {
            for (uint256 i; i < outputSize; ++i) {
                tradeInfos[i] = openTradeInfos[offset + i];
            }
        }
    }

    function getOpenLimitOrder(uint256 limitIndex) external view override returns (OpenLimitOrder memory order) {
        uint256 id = openLimitOrderIds[limitIndex];
        if (id == 0 || id >= openLimitOrders.length) return order;
        order = openLimitOrders[id];
    }

    function getOpenLimitOrdersCount(address trader, uint256 pairIndex) external view override returns (uint256) {
        return openLimitOrdersCount[trader.traderCountKeyFor(pairIndex)];
    }

    function getOpenLimitOrders(
        uint256 offset,
        uint256 count
    )
        external
        view
        override
        returns (OpenLimitOrder[] memory orders)
    {
        // The 0th element in the array is skipped to make the index 1-based.
        if (offset == 0) return new OpenLimitOrder[](0);

        // If the count requested is 0 or the offset is beyond the array length, return an empty array.
        if (count == 0 || offset >= openLimitOrders.length) return new OpenLimitOrder[](0);

        // Calculate the size of the array to return: smaller of `count` or `openLimitOrders.length - offset`.
        uint256 outputSize = (offset + count > openLimitOrders.length) ? openLimitOrders.length - offset : count;

        // Initialize the array of results and populate.
        orders = new OpenLimitOrder[](outputSize);
        unchecked {
            for (uint256 i = 0; i < outputSize; ++i) {
                orders[i] = openLimitOrders[offset + i];
            }
        }
    }
}
