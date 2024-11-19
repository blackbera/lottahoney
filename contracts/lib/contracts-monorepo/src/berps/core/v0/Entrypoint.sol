// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IPyth } from "@pythnetwork/IPyth.sol";
import { PythErrors } from "@pythnetwork/PythErrors.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { PayableMulticallable } from "transient-goodies/PayableMulticallable.sol";

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { Utils } from "../../../libraries/Utils.sol";
import { BerpsErrors } from "../../utils/BerpsErrors.sol";
import { Delegatable } from "../../utils/Delegatable.sol";
import { PriceUtils } from "../../utils/PriceUtils.sol";
import { TradeUtils } from "../../utils/TradeUtils.sol";

import { IDelegatable, IEntrypoint } from "../../interfaces/v0/IEntrypoint.sol";
import { IOrders } from "../../interfaces/v0/IOrders.sol";
import { IFeesMarkets } from "../../interfaces/v0/IFeesMarkets.sol";
import { IMarkets } from "../../interfaces/v0/IMarkets.sol";
import { IFeesAccrued } from "../../interfaces/v0/IFeesAccrued.sol";
import { ISettlement } from "../../interfaces/v0/ISettlement.sol";

/// @notice Entrypoint serves as the entrypoint for all trading actions.
contract Entrypoint is UUPSUpgradeable, Delegatable, PayableMulticallable, IEntrypoint {
    using TradeUtils for address;
    using PriceUtils for IPyth;
    using PriceUtils for int64;
    using Utils for bytes4;

    // Contracts (constant)
    IOrders public orders;
    IFeesMarkets public feesMarkets;
    IFeesAccrued public feesAccrued;

    // Params (constant)
    uint256 constant PRECISION = 1e10;
    int8 constant MAX_SL_P = 75; // -75% PNL

    // Params (adjustable)
    IPyth public pyth;
    uint64 public staleTolerance;
    uint256 public maxPosHoney; // 1e18 (eg. 75000 * 1e18)

    // State
    bool public isPaused; // Prevent opening new trades
    bool public isDone; // Prevent any interaction with the contract

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGov { }

    /// @inheritdoc IEntrypoint
    function initialize(
        address _pyth,
        address _orders,
        address _feesMarkets,
        address _feesAccrued,
        uint64 _staleTolerance,
        uint256 _maxPosHoney
    )
        external
        initializer
    {
        if (
            _pyth == address(0) || _orders == address(0) || _feesMarkets == address(0) || _feesAccrued == address(0)
                || _maxPosHoney == 0
        ) BerpsErrors.WrongParams.selector.revertWith();

        orders = IOrders(_orders);
        feesMarkets = IFeesMarkets(_feesMarkets);
        feesAccrued = IFeesAccrued(_feesAccrued);

        pyth = IPyth(_pyth);
        staleTolerance = _staleTolerance;
        maxPosHoney = _maxPosHoney;
    }

    // Modifiers
    modifier onlyGov() {
        isGov();
        _;
    }

    modifier notContract() {
        isNotContract();
        _;
    }

    modifier notDone() {
        isNotDone();
        _;
    }

    // Saving code size by calling these functions inside modifiers
    function isGov() private view {
        if (msg.sender != orders.gov()) BerpsErrors.Unauthorized.selector.revertWith();
    }

    function isNotContract() private view {
        if (tx.origin != msg.sender) BerpsErrors.Unauthorized.selector.revertWith();
    }

    function isNotDone() private view {
        if (isDone) BerpsErrors.Done.selector.revertWith();
    }

    // Manage params
    function setStaleTolerance(uint64 _staleTolerance) external onlyGov {
        staleTolerance = _staleTolerance;
        emit StaleToleranceUpdated(_staleTolerance);
    }

    function setPyth(IPyth _pyth) external onlyGov {
        if (address(_pyth) == address(0)) BerpsErrors.WrongParams.selector.revertWith();
        pyth = _pyth;
        emit PythUpdated(_pyth);
    }

    function setMaxPosHoney(uint256 value) external onlyGov {
        if (value == 0) BerpsErrors.WrongParams.selector.revertWith();
        maxPosHoney = value;
        emit MaxPosHoneyUpdated(value);
    }

    // Manage state
    function pause() external onlyGov {
        isPaused = !isPaused;
        emit Paused(isPaused);
    }

    function done() external onlyGov {
        isDone = !isDone;
        emit Done(isDone);
    }

    // Open new trade (MARKET/LIMIT)
    function openTrade(
        IOrders.Trade memory t,
        ISettlement.TradeType orderType,
        int64 slippageP, // for market orders only
        bytes[] calldata priceUpdateData
    )
        external
        payable
        standalonePayable
        notContract
        notDone
    {
        // trading validity checks
        if (isPaused) BerpsErrors.Paused.selector.revertWith();
        address sender = _msgSender();
        validateTrade(sender, t);

        // process trade with pyth price
        orders.transferHoney(sender, address(orders), t.positionSizeHoney);
        (int64 currentPrice, int64 currentPriceHoney) = getPrice(t.pairIndex, priceUpdateData, t.buy, true);

        if (orderType == ISettlement.TradeType.LIMIT) {
            registerOpenLimitOrder(sender, t, currentPrice, orders.settlement());
        } else {
            ISettlement(orders.settlement()).openTradeMarketCallback(
                currentPrice,
                currentPriceHoney,
                IOrders.Trade(sender, t.pairIndex, 0, 0, t.positionSizeHoney, 0, t.buy, t.leverage, t.tp, t.sl),
                t.openPrice,
                slippageP
            );
        }
    }

    // Close trade (MARKET) for _msgSender()
    function closeTradeMarket(
        uint256 tradeIndex,
        bytes[] calldata priceUpdateData
    )
        external
        payable
        standalonePayable
        notContract
        notDone
    {
        ISettlement c = ISettlement(orders.settlement());

        IOrders.Trade memory t = orders.getOpenTrade(tradeIndex);
        if (t.leverage == 0) BerpsErrors.NoTrade.selector.revertWith();
        if (t.trader != _msgSender()) BerpsErrors.Unauthorized.selector.revertWith();

        (int64 currentPrice,) = getPrice(t.pairIndex, priceUpdateData, t.buy, false);
        c.closeTradeMarketCallback(currentPrice, tradeIndex);
    }

    // Manage limit order (OPEN)
    function updateOpenLimitOrder(
        uint256 limitIndex,
        int64 newPrice, // PRECISION
        int64 tp,
        int64 sl,
        bytes[] calldata priceUpdateData
    )
        external
        payable
        standalonePayable
        notContract
        notDone
    {
        IOrders.OpenLimitOrder memory o = orders.getOpenLimitOrder(limitIndex);
        if (o.leverage == 0) BerpsErrors.NoLimit.selector.revertWith();
        if (o.trader != _msgSender()) BerpsErrors.Unauthorized.selector.revertWith();

        // check limit (reversal) conditions
        (int64 currentPrice,) = getPrice(o.pairIndex, priceUpdateData, o.buy, true);
        // the open price must be a more favorable entry than the current price
        // Long: newPrice must be lower than currentPrice, Short: newPrice must be higher than currentPrice
        if (o.buy ? newPrice >= currentPrice : newPrice <= currentPrice) {
            BerpsErrors.WrongLimitPrice.selector.revertWith();
        }
        if (tp > 0 && (o.buy ? tp <= newPrice : tp >= newPrice)) BerpsErrors.WrongTp.selector.revertWith();
        if (sl > 0 && (o.buy ? sl >= newPrice : sl <= newPrice)) BerpsErrors.WrongSl.selector.revertWith();

        o.minPrice = newPrice;
        o.maxPrice = newPrice;
        o.tp = tp;
        o.sl = sl;

        orders.updateOpenLimitOrder(o);
        orders.settlement().setLimitLastUpdated(limitIndex);

        emit OpenLimitUpdated(limitIndex, o.pairIndex, o.buy, newPrice, tp, sl);
    }

    function cancelOpenLimitOrder(uint256 limitIndex) external notContract notDone {
        IOrders.OpenLimitOrder memory o = orders.getOpenLimitOrder(limitIndex);
        if (o.leverage == 0) BerpsErrors.NoLimit.selector.revertWith();
        if (o.trader != _msgSender()) BerpsErrors.Unauthorized.selector.revertWith();

        orders.unregisterOpenLimitOrder(limitIndex);
        ISettlement(orders.settlement()).removeLimitLastUpdated(limitIndex);
        orders.transferHoney(address(orders), o.trader, o.positionSize);

        emit OpenLimitCanceled(limitIndex, o.pairIndex);
    }

    // Manage open trade (TP/SL)
    function updateTp(uint256 tradeIndex, int64 newTp) external notContract notDone {
        IOrders.Trade memory t = orders.getOpenTrade(tradeIndex);
        if (t.leverage == 0) BerpsErrors.NoTrade.selector.revertWith();
        if (t.trader != _msgSender()) BerpsErrors.Unauthorized.selector.revertWith();
        if (newTp == t.tp) BerpsErrors.WrongTp.selector.revertWith();

        ISettlement c = ISettlement(orders.settlement());

        // validate tp for the lower bound
        if (newTp > 0 && (t.buy ? newTp <= t.openPrice : newTp >= t.openPrice)) {
            BerpsErrors.WrongTp.selector.revertWith();
        }

        // validate tp for the upper bound
        int64 correctTp = newTp.correctTp(t.openPrice, t.buy, t.leverage);
        if (newTp > 0 && (t.buy ? newTp > correctTp : newTp < correctTp)) BerpsErrors.WrongTp.selector.revertWith();

        orders.updateTp(tradeIndex, correctTp);
        address(c).setTpLastUpdated(tradeIndex);

        emit TpUpdated(tradeIndex, t.pairIndex, t.buy, correctTp);
    }

    function updateSl(
        uint256 tradeIndex,
        int64 newSl,
        bytes[] calldata priceUpdateData
    )
        external
        payable
        standalonePayable
        notContract
        notDone
    {
        IOrders.Trade memory t = orders.getOpenTrade(tradeIndex);
        if (t.leverage == 0) BerpsErrors.NoTrade.selector.revertWith();
        if (t.trader != _msgSender()) BerpsErrors.Unauthorized.selector.revertWith();
        if (newSl == t.sl) BerpsErrors.WrongSl.selector.revertWith();

        int64 correctedMaxSl = newSl.correctSl(t.openPrice, t.buy, t.leverage);
        if (
            newSl > 0
                && (
                    t.buy
                        ? (newSl > t.openPrice) || (newSl < correctedMaxSl)
                        : (newSl < t.openPrice) || (newSl > correctedMaxSl)
                )
        ) BerpsErrors.WrongSl.selector.revertWith();

        registerNewSl(tradeIndex, newSl, t, priceUpdateData);
    }

    /// @inheritdoc IEntrypoint
    function executeLimitOrder(
        uint256 index,
        bytes[] calldata priceUpdateData
    )
        external
        payable
        standalonePayable
        notDone
        notContract
    {
        ISettlement c = ISettlement(orders.settlement());

        // Check if there is a open limit order at the given index.
        IOrders.OpenLimitOrder memory o = orders.getOpenLimitOrder(index);
        if (o.leverage > 0) {
            (int64 currentPrice, int64 currentPriceHoney) = getPrice(o.pairIndex, priceUpdateData, o.buy, true);
            c.executeLimitOpenOrderCallback(currentPrice, currentPriceHoney, o, msg.sender, isPaused);
            return;
        }

        // If it's not a limit order, try executing on a open trade at the given index.
        IOrders.Trade memory t = orders.getOpenTrade(index);
        if (t.leverage > 0) {
            (int64 currentPrice,) = getPrice(t.pairIndex, priceUpdateData, t.buy, false);
            c.executeLimitCloseOrderCallback(currentPrice, index, msg.sender);
            return;
        }

        // If no open limit order or trade is found, let the executor know.
        emit InvalidLimitExecution(index);
    }

    /// @inheritdoc IDelegatable
    /// @dev Overriden here to allow the value refund to occur through the PayableMulticall contract.
    function refundValue() external payable override(Delegatable, IDelegatable) notContract {
        // Refund any value set by multicalls, using the PayableMulticall contract.
        _returnRemainingValue(msg.sender);

        // Refund any remaining value not from multicalls, similar as in Delegatable.
        if (address(this).balance > 0) SafeTransferLib.safeTransferETH(msg.sender, address(this).balance);
    }

    // Helpers
    function validateTrade(address sender, IOrders.Trade memory t) internal view {
        IMarkets markets = orders.markets();

        if (
            orders.getOpenTradesCount(sender, t.pairIndex) + orders.getOpenLimitOrdersCount(sender, t.pairIndex)
                >= orders.maxTradesPerPair()
        ) BerpsErrors.MaxTradesPerPair.selector.revertWith();

        if (t.positionSizeHoney > maxPosHoney) BerpsErrors.AboveMaxPos.selector.revertWith();
        if (t.positionSizeHoney > markets.groupMaxCollateral(t.pairIndex)) {
            BerpsErrors.AboveMaxGroupCollateral.selector.revertWith();
        }
        if (t.positionSizeHoney * t.leverage < markets.pairMinLevPosHoney(t.pairIndex)) {
            BerpsErrors.BelowMinPos.selector.revertWith();
        }

        if (
            t.leverage == 0 || t.leverage < markets.pairMinLeverage(t.pairIndex)
                || t.leverage > markets.pairMaxLeverage(t.pairIndex)
        ) BerpsErrors.LeverageIncorrect.selector.revertWith();

        if (t.tp > 0 && (t.buy ? t.tp <= t.openPrice : t.tp >= t.openPrice)) BerpsErrors.WrongTp.selector.revertWith();
        if (t.sl > 0 && (t.buy ? t.sl >= t.openPrice : t.sl <= t.openPrice)) BerpsErrors.WrongSl.selector.revertWith();

        (int64 priceImpactP,) =
            feesMarkets.getTradePriceImpact(0, t.pairIndex, t.buy, t.positionSizeHoney * t.leverage);
        if (priceImpactP * int256(t.leverage) > feesMarkets.maxNegativePnlOnOpenP()) {
            BerpsErrors.PriceImpactTooHigh.selector.revertWith();
        }
    }

    function registerOpenLimitOrder(
        address sender,
        IOrders.Trade memory t,
        int64 price,
        address settlement
    )
        internal
    {
        // check limit (reversal) conditions
        // the open price must be a more favorable entry than the current price
        // Long: t.openPrice must be lower than price, Short: t.openPrice must be higher than price
        if (t.buy ? t.openPrice >= price : t.openPrice <= price) BerpsErrors.WrongLimitPrice.selector.revertWith();

        uint256 index = orders.globalIndex();
        IOrders.OpenLimitOrder memory o = IOrders.OpenLimitOrder(
            sender, t.pairIndex, index, t.positionSizeHoney, t.buy, t.leverage, t.tp, t.sl, t.openPrice, t.openPrice
        );

        orders.storeOpenLimitOrder(o);

        settlement.setLimitLastUpdated(index);

        emit OpenLimitPlaced(o);
    }

    function registerNewSl(
        uint256 tradeIndex,
        int64 newSl,
        IOrders.Trade memory t,
        bytes[] calldata priceUpdateData
    )
        internal
    {
        ISettlement c = ISettlement(orders.settlement());

        if (newSl == 0 || !orders.markets().guaranteedSlEnabled(t.pairIndex)) {
            orders.updateSl(tradeIndex, newSl);
            address(c).setSlLastUpdated(tradeIndex);
            emit SlUpdated(tradeIndex, t.pairIndex, t.buy, newSl);
        } else {
            (int64 currentPrice, int64 currentPriceHoney) = getPrice(t.pairIndex, priceUpdateData, t.buy, true);
            c.updateSlCallback(currentPrice, currentPriceHoney, tradeIndex, newSl);
        }
    }

    /// @notice Gets the current price for the given pair from Pyth after updating the price feeds.
    /// @dev Extra value is not refunded and remains in this contract.
    /// @dev This function reverts (by Pyth) if the provided price update is older than the configured stale timeout or
    /// the update data is invalid.
    /// @return currentPrice for the given pair index.
    /// @return currentPriceHoney for HONEY in terms of the desired quote currency.
    function getPrice(
        uint256 pairIndex,
        bytes[] calldata priceUpdateData,
        bool buy,
        bool isOpen
    )
        internal
        returns (int64 currentPrice, int64 currentPriceHoney)
    {
        IMarkets.Feed memory feed = orders.markets().pairFeed(pairIndex);

        // Update the on-chain Pyth price(s), ensuring there are sufficiently recent updates for the required feeds.
        uint256 fee = useValue(pyth.getUpdateFee(priceUpdateData));
        if (msg.value < fee) {
            PythErrors.InsufficientFee.selector.revertWith();
        }
        pyth.parsePriceFeedUpdates{ value: fee }(
            priceUpdateData, feed.ids, uint64(block.timestamp) - staleTolerance, type(uint64).max
        );

        // Read the current price from Pyth, requiring validity
        currentPrice = pyth.getPythExecutionPrice(feed, buy, isOpen);
        currentPriceHoney = pyth.getPythExecutionPriceHoney(feed);
    }

    function pairMaxLeverage(IMarkets markets, uint256 pairIndex) internal view returns (uint256) {
        uint256 max = ISettlement(orders.settlement()).pairMaxLeverage(pairIndex);
        return max > 0 ? max : markets.pairMaxLeverage(pairIndex);
    }
}
