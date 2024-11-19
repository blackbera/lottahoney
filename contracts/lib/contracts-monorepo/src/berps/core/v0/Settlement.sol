// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { SafeCastLib } from "solady/src/utils/SafeCastLib.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { Utils } from "../../../libraries/Utils.sol";
import { BerpsErrors } from "../../utils/BerpsErrors.sol";
import { PriceUtils } from "../../utils/PriceUtils.sol";
import { TradeUtils } from "../../utils/TradeUtils.sol";

import "../../interfaces/v0/IOrders.sol";
import { ISettlement } from "../../interfaces/v0/ISettlement.sol";
import { IFeesMarkets } from "../../interfaces/v0/IFeesMarkets.sol";
import { IFeesAccrued } from "../../interfaces/v0/IFeesAccrued.sol";

/// @notice Settlement manages state changes for all trading actions.
contract Settlement is UUPSUpgradeable, ISettlement {
    using SafeTransferLib for address;
    using TradeUtils for ISettlement.CancelReason;
    using PriceUtils for int64;
    using Utils for bytes4;

    // Params (constant)
    uint64 constant PRECISION = 1e10; // 10 decimals
    int64 constant MAX_SL_P = 75; // -75% PNL
    int64 constant MAX_GAIN_P = 900; // 900% PnL (10x)
    uint64 constant MAX_EXECUTE_TIMEOUT = 6; // 6 blocks of timeout
    uint256 constant MAX_PERCENT = 100; // 100%

    // Contracts (constant)
    IOrders public orders;
    IFeesMarkets public feesMarkets;
    IFeesAccrued public feesAccrued;

    // Contracts (updateable)
    IVault public vault;
    IReferrals public referrals;

    // State
    uint64 public canExecuteTimeout; // How long after an update to TP/SL/Limit to wait before its executable
    uint256 public updateSlFeeP; // % of open fee charged for updating SL
    uint256 public liqFeeP; // % of position size (collateral) to liquidator

    // Last Updated State (block numbers), used for both open limit orders and open trades
    mapping(uint256 index => LastUpdated) private _tradeLastUpdated;

    // Storage/State
    mapping(uint256 => uint256) public pairMaxLeverage;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGov { }

    /// @inheritdoc ISettlement
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
        external
        initializer
    {
        if (
            _orders == address(0) || _feesMarkets == address(0) || _referrals == address(0)
                || _feesAccrued == address(0) || _vault == address(0) || _honey == address(0)
                || _canExecuteTimeout > MAX_EXECUTE_TIMEOUT || _updateSlFeeP > MAX_PERCENT || _liqFeeP > MAX_PERCENT
        ) BerpsErrors.WrongParams.selector.revertWith();

        orders = IOrders(_orders);
        feesMarkets = IFeesMarkets(_feesMarkets);
        referrals = IReferrals(_referrals);
        feesAccrued = IFeesAccrued(_feesAccrued);
        vault = IVault(_vault);

        canExecuteTimeout = _canExecuteTimeout;
        updateSlFeeP = _updateSlFeeP;
        liqFeeP = _liqFeeP;

        _honey.safeApprove(_vault, type(uint256).max);
    }

    // Modifiers
    modifier onlyGov() {
        isGov();
        _;
    }

    modifier onlyEntrypoint() {
        isEntrypoint();
        _;
    }

    modifier onlyManager() {
        isManager();
        _;
    }

    // Saving code size by calling these functions inside modifiers
    function isGov() internal view {
        if (msg.sender != orders.gov()) BerpsErrors.Unauthorized.selector.revertWith();
    }

    function isEntrypoint() internal view {
        if (msg.sender != orders.entrypoint()) BerpsErrors.Unauthorized.selector.revertWith();
    }

    function isManager() internal view {
        if (msg.sender != feesMarkets.manager()) BerpsErrors.Unauthorized.selector.revertWith();
    }

    // Manage params
    function setPairMaxLeverage(uint256 pairIndex, uint256 maxLeverage) external onlyManager {
        _setPairMaxLeverage(pairIndex, maxLeverage);
    }

    function setPairMaxLeverageArray(uint256[] calldata indices, uint256[] calldata values) external onlyManager {
        if (indices.length != values.length) {
            BerpsErrors.WrongParams.selector.revertWith();
        }

        for (uint256 i; i < indices.length;) {
            _setPairMaxLeverage(indices[i], values[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _setPairMaxLeverage(uint256 pairIndex, uint256 maxLeverage) internal {
        if (maxLeverage > getMarkets().MAX_LEVERAGE()) BerpsErrors.WrongParams.selector.revertWith();
        pairMaxLeverage[pairIndex] = maxLeverage;
        emit PairMaxLeverageUpdated(pairIndex, maxLeverage);
    }

    function setCanExecuteTimeout(uint64 _canExecuteTimeout) external onlyGov {
        if (_canExecuteTimeout > MAX_EXECUTE_TIMEOUT) {
            BerpsErrors.WrongParams.selector.revertWith();
        }
        canExecuteTimeout = _canExecuteTimeout;
        emit CanExecuteTimeoutUpdated(_canExecuteTimeout);
    }

    function setUpdateSlFeeP(uint256 _updateSlFeeP) external onlyGov {
        if (_updateSlFeeP > MAX_PERCENT) {
            BerpsErrors.WrongParams.selector.revertWith();
        }
        updateSlFeeP = _updateSlFeeP;
        emit UpdateSlFeePUpdated(_updateSlFeeP);
    }

    function setLiqFeeP(uint256 _liqFeeP) external onlyGov {
        if (_liqFeeP > MAX_PERCENT) {
            BerpsErrors.WrongParams.selector.revertWith();
        }
        liqFeeP = _liqFeeP;
        emit LiqFeePUpdated(_liqFeeP);
    }

    // Callbacks
    function openTradeMarketCallback(
        int64 currentPrice,
        int64 currentPriceHoney,
        IOrders.Trade memory t,
        int64 wantedPrice, // PRECISION
        int64 slippageP // PRECISION (%)
    )
        external
        onlyEntrypoint
    {
        (int64 priceImpactP, int64 priceAfterImpact) =
            feesMarkets.getTradePriceImpact(currentPrice, t.pairIndex, t.buy, t.positionSizeHoney * t.leverage);
        t.openPrice = priceAfterImpact;

        int64 maxSlippage = SafeCastLib.toInt64((int256(wantedPrice) * int256(slippageP)) / 100 / int64(PRECISION));
        if (t.buy ? t.openPrice > wantedPrice + maxSlippage : t.openPrice < wantedPrice - maxSlippage) {
            BerpsErrors.SlippageExceeded.selector.revertWith();
        }

        CancelReason cancelReason = getOpenTradeCancelReason(t, priceImpactP);
        if (cancelReason != CancelReason.NONE) cancelReason.revertFor();

        uint256 openFee = registerTrade(t, currentPriceHoney, t.trader);
        emit MarketOpened(t, priceImpactP, openFee);
    }

    function closeTradeMarketCallback(int64 currentPrice, uint256 tradeIndex) external onlyEntrypoint {
        IOrders.Trade memory t = orders.getOpenTrade(tradeIndex);
        if (t.leverage == 0) BerpsErrors.NoTrade.selector.revertWith();

        if (TradeUtils.isCloseInTimeout(address(this), tradeIndex)) BerpsErrors.InTimeout.selector.revertWith();

        IOrders.TradeInfo memory i = orders.getOpenTradeInfo(tradeIndex);
        if (i.openInterestHoney == 0) BerpsErrors.NoTrade.selector.revertWith();

        Values memory v;
        v.posHoney = (t.initialPosToken * uint64(i.tokenPriceHoney)) / PRECISION;
        v.profitP = currentPrice.currentPercentProfit(t.openPrice, t.buy, t.leverage);
        v.levPosHoney = v.posHoney * t.leverage;

        ClosingFees memory fees;
        fees.borrowFee = feesAccrued.getTradeBorrowingFee(
            IFeesAccrued.BorrowingFeeInput(t.pairIndex, tradeIndex, t.buy, v.posHoney, t.leverage)
        );
        (v.honeySentToTrader) = unregisterTrade(
            t,
            t.trader,
            v.profitP,
            v.posHoney,
            i.openInterestHoney,
            (v.levPosHoney * getMarkets().pairCloseFeeP(t.pairIndex)) / 100 / PRECISION, // close fee
            0, // Market close accrues no limit execution fee.
            fees // borrowFee set in this struct
        );

        emit MarketClosed(t, currentPrice, v.profitP, int256(v.honeySentToTrader) - int256(v.posHoney), fees);
    }

    function executeLimitOpenOrderCallback(
        int64 currentPrice,
        int64 currentPriceHoney,
        IOrders.OpenLimitOrder memory o,
        address executor,
        bool isPaused
    )
        external
        onlyEntrypoint
    {
        CancelReason cancelReason = isPaused
            ? CancelReason.PAUSED
            : (isInTimeout(IOrders.LimitOrder.OPEN, o.index) ? CancelReason.IN_TIMEOUT : CancelReason.NONE);

        if (cancelReason == CancelReason.NONE) {
            (int64 priceImpactP, int64 priceAfterImpact) =
                feesMarkets.getTradePriceImpact(currentPrice, o.pairIndex, o.buy, o.positionSize * o.leverage);
            IOrders.Trade memory t = IOrders.Trade(
                o.trader, o.pairIndex, 0, 0, o.positionSize, priceAfterImpact, o.buy, o.leverage, o.tp, o.sl
            );

            // check limit (reversal) conditions for CancelReason.NOT_HIT and other opening trade conditions
            // the current price must be an entry at least or more favorable than the order's limit open price
            // Long: priceAfterImpact must be <= o.minPrice, Short: priceAfterImpact must be >= o.maxPrice
            cancelReason = (o.buy ? priceAfterImpact > o.minPrice : priceAfterImpact < o.maxPrice)
                ? CancelReason.NOT_HIT
                : getOpenTradeCancelReason(t, priceImpactP);

            if (cancelReason == CancelReason.NONE) {
                uint256 openFee = registerTrade(t, currentPriceHoney, executor);
                orders.unregisterOpenLimitOrder(o.index);
                delete _tradeLastUpdated[o.index];

                emit LimitOpenExecuted(executor, o.index, t, priceImpactP, openFee);
            } else if (cancelReason == CancelReason.SL_REACHED) {
                // If the limit order's SL is reached, entering this position is not possible.

                // Distribute the limit fee to the executor.
                uint256 limitFee =
                    (o.positionSize * o.leverage * getMarkets().pairLimitOrderFeeP(o.pairIndex)) / 100 / PRECISION;
                transferFromOrdersToAddress(executor, limitFee);
                o.positionSize -= limitFee;

                // Cancel the limit order and return the remaining collateral to the trader.
                orders.unregisterOpenLimitOrder(o.index);
                delete _tradeLastUpdated[o.index];
                transferFromOrdersToAddress(o.trader, o.positionSize);

                emit OpenLimitSlCanceled(o.index, o.pairIndex, t.openPrice, o.sl);
            }
        }

        if (cancelReason != CancelReason.NONE) {
            emit LimitOpenCanceled(executor, o.index, cancelReason, currentPrice, o.minPrice, o.maxPrice);
        }
    }

    function executeLimitCloseOrderCallback(
        int64 currentPrice,
        uint256 tradeIndex,
        address executor
    )
        external
        onlyEntrypoint
    {
        IOrders.Trade memory t = orders.getOpenTrade(tradeIndex);
        IOrders.TradeInfo memory i = orders.getOpenTradeInfo(tradeIndex);
        CancelReason cancelReason =
            (t.leverage == 0 || i.openInterestHoney == 0) ? CancelReason.NO_TRADE : CancelReason.NONE;

        IMarkets markets = getMarkets();
        Values memory v;
        ClosingFees memory fees;

        if (cancelReason == CancelReason.NONE) {
            v.posHoney = (t.initialPosToken * uint64(i.tokenPriceHoney)) / PRECISION;
            v.levPosHoney = v.posHoney * t.leverage;

            // If the price is less favorable than the open price for the trader,
            // check if LIQ or SL is triggered.
            if (t.buy ? currentPrice < t.openPrice : currentPrice > t.openPrice) {
                (v.liqPrice, fees.borrowFee) = feesAccrued.getTradeLiquidationPrice(
                    IFeesAccrued.LiqPriceInput(t.pairIndex, t.index, t.openPrice, t.buy, v.posHoney, t.leverage)
                );
                if (t.buy ? currentPrice <= v.liqPrice : currentPrice >= v.liqPrice) {
                    // First check if the order can be liquidated.
                    v.orderType = IOrders.LimitOrder.LIQ;
                    v.reward1 = (v.posHoney * liqFeeP) / 100;
                    v.price = v.liqPrice;
                } else if (t.sl > 0 && (t.buy ? currentPrice <= t.sl : currentPrice >= t.sl)) {
                    // Then check if the order has an SL and it is executable.
                    v.orderType = IOrders.LimitOrder.SL;
                    v.reward1 = (v.levPosHoney * markets.pairLimitOrderFeeP(t.pairIndex)) / 100 / PRECISION;
                    v.price = t.sl;
                }
            } else if (t.tp > 0 && (t.buy ? currentPrice >= t.tp : currentPrice <= t.tp)) {
                // The price is more favorable than the open price for the trader,
                // so check if the order has a TP and it is executable.
                v.orderType = IOrders.LimitOrder.TP;
                v.reward1 = (v.levPosHoney * markets.pairLimitOrderFeeP(t.pairIndex)) / 100 / PRECISION;
                v.price = t.tp;
            }

            // Check that the order type is one of LIQ, SL, or TP -> `v.price` must have been set to a nonzero value.
            // Then, also check that the trade is not in a timeout for executing a valid order type.
            cancelReason = v.price == 0
                ? CancelReason.NOT_HIT
                : (isInTimeout(v.orderType, tradeIndex) ? CancelReason.IN_TIMEOUT : CancelReason.NONE);
        }

        if (cancelReason != CancelReason.NONE) {
            emit LimitCloseCanceled(executor, t.index, cancelReason, currentPrice, t.tp, t.sl, v.liqPrice);
            return;
        }

        v.profitP = v.price.currentPercentProfit(t.openPrice, t.buy, t.leverage);

        v.honeySentToTrader = unregisterTrade(
            t,
            executor,
            v.profitP,
            v.posHoney,
            i.openInterestHoney,
            v.orderType == IOrders.LimitOrder.LIQ
                ? v.reward1 // liquidation fee
                : (v.levPosHoney * markets.pairCloseFeeP(t.pairIndex)) / 100 / PRECISION, // close fee
            v.reward1, // limit execution fee
            fees // borrow fee set in this struct
        );

        emit LimitCloseExecuted(
            executor, t, v.orderType, v.price, v.profitP, int256(v.honeySentToTrader) - int256(v.posHoney), fees
        );
    }

    function updateSlCallback(
        int64 currentPrice,
        int64 currentPriceHoney,
        uint256 tradeIndex,
        int64 newSl
    )
        external
        onlyEntrypoint
    {
        IOrders.Trade memory t = orders.getOpenTrade(tradeIndex);
        IOrders.TradeInfo memory i = orders.getOpenTradeInfo(tradeIndex);
        CancelReason cancelReason =
            (t.leverage == 0 || i.openInterestHoney == 0) ? CancelReason.NO_TRADE : CancelReason.NONE;

        if (cancelReason == CancelReason.NONE) {
            Values memory v;

            v.tokenPriceHoney = currentPriceHoney;
            v.levPosHoney =
                (t.initialPosToken * uint64(i.tokenPriceHoney) * t.leverage) * updateSlFeeP / 100 / PRECISION;

            // Charge in HONEY if collateral in storage or token if collateral in vault
            v.reward1 = t.positionSizeHoney > 0
                ? orders.handleDevGovFees(t.pairIndex, v.levPosHoney)
                : (orders.handleDevGovFees(t.pairIndex, v.levPosHoney) * uint64(v.tokenPriceHoney)) / PRECISION;

            t.positionSizeHoney -= v.reward1;
            t.initialPosToken -= (v.reward1 * PRECISION) / uint64(i.tokenPriceHoney);
            orders.updateTrade(t);

            cancelReason =
                (t.buy ? newSl > currentPrice : newSl < currentPrice) ? CancelReason.SL_REACHED : CancelReason.NONE;
        }

        if (cancelReason != CancelReason.NONE) cancelReason.revertFor();

        orders.updateSl(tradeIndex, newSl);
        _tradeLastUpdated[tradeIndex].sl = uint64(block.number);

        emit SlUpdated(t.index, t.pairIndex, t.buy, newSl, t.initialPosToken, t.positionSizeHoney);
    }

    // Shared code between market & limit settlement
    function registerTrade(
        IOrders.Trade memory trade,
        int64 currentPriceHoney,
        address executor
    )
        internal
        returns (uint256)
    {
        IMarkets markets = getMarkets();

        Values memory v;

        v.levPosHoney = trade.positionSizeHoney * trade.leverage;
        v.tokenPriceHoney = currentPriceHoney;

        // 1. Charge referral fee (if applicable)
        if (referrals.getTraderReferrer(trade.trader) != address(0)) {
            // Use this variable to store lev pos honey for dev/gov fees after
            // referral fees and before volumeReferredHoney increases
            v.posHoney =
                (v.levPosHoney * (100 * PRECISION - referrals.getPercentOfOpenFeeP(trade.trader))) / 100 / PRECISION;

            v.reward1 =
                referrals.distributePotentialReward(trade.trader, v.levPosHoney, markets.pairOpenFeeP(trade.pairIndex));
            trade.positionSizeHoney -= v.reward1;
        }

        // 2. Charge opening fee - referral fee (if applicable)
        v.reward2 = orders.handleDevGovFees(trade.pairIndex, (v.posHoney > 0 ? v.posHoney : v.levPosHoney));
        trade.positionSizeHoney -= v.reward2;

        // 3. Charge Limit Order Fee
        if (executor != trade.trader) {
            v.reward3 = (v.levPosHoney * markets.pairLimitOrderFeeP(trade.pairIndex)) / 100 / PRECISION;
            transferFromOrdersToAddress(executor, v.reward3);
            trade.positionSizeHoney -= v.reward3;
        }

        // 4. Set trade final details
        trade.index = orders.globalIndex();
        trade.initialPosToken = (trade.positionSizeHoney * PRECISION) / uint64(v.tokenPriceHoney);

        trade.tp = trade.tp.correctTp(trade.openPrice, trade.buy, trade.leverage);
        trade.sl = trade.sl.correctSl(trade.openPrice, trade.buy, trade.leverage);

        // 5. Call other contracts
        feesMarkets.storeTradeInitialAccFees(trade.pairIndex, trade.index, trade.buy);
        markets.updateGroupCollateral(trade.pairIndex, trade.positionSizeHoney, trade.buy, true);
        feesAccrued.handleTradeAction(
            trade.pairIndex, trade.index, trade.positionSizeHoney * trade.leverage, true, trade.buy
        );

        // 6. Store final trade in storage contract
        orders.storeTrade(trade, IOrders.TradeInfo(v.tokenPriceHoney, trade.positionSizeHoney * trade.leverage));

        // 7. Store tradeLastUpdated
        LastUpdated storage lastUpdated = _tradeLastUpdated[trade.index];
        lastUpdated.tp = uint64(block.number);
        lastUpdated.sl = uint64(block.number);
        lastUpdated.created = uint64(block.number);

        return v.reward1 + v.reward2 + v.reward3;
    }

    /// @param fees borrowFee must be set on the ClosingFees fees struct before calling this function
    function unregisterTrade(
        IOrders.Trade memory trade,
        address executor,
        int256 percentProfit, // PRECISION
        uint256 currentHoneyPos, // 1e18
        uint256 openInterestHoney, // 1e18
        uint256 closeFeeHoney, // 1e18
        uint256 limitFeeHoney, // 1e18
        ClosingFees memory fees
    )
        internal
        returns (uint256 honeySentToTrader)
    {
        bool limitOrder = executor != trade.trader;

        // 1. Calculate net PnL (after all closing and holding fees)
        fees.closeFee = closeFeeHoney + (limitOrder ? limitFeeHoney : 0);
        honeySentToTrader = _getTradeValue(trade, currentHoneyPos, percentProfit, fees);

        // 2. Calls to other contracts
        getMarkets().updateGroupCollateral(trade.pairIndex, openInterestHoney / trade.leverage, trade.buy, false);
        feesAccrued.handleTradeAction(trade.pairIndex, trade.index, openInterestHoney, false, trade.buy);

        // 3. Unregister trade from storage
        orders.unregisterTrade(trade.index);

        // 4.1 If collateral in storage (opened after update)
        if (trade.positionSizeHoney > 0) {
            Values memory v;

            // 4.1.1 HONEY close fee rewards to vault
            v.reward1 = closeFeeHoney;
            transferFromOrdersToAddress(address(this), v.reward1);
            vault.distributeReward(v.reward1);

            // 4.1.2 HONEY limit fee to executor
            if (limitOrder) {
                v.reward2 = limitFeeHoney;
                transferFromOrdersToAddress(executor, v.reward2);
            }

            // 4.1.3 Take HONEY from vault if winning trade or send HONEY to vault if losing trade
            uint256 honeyLeftInStorage = currentHoneyPos - v.reward1 - v.reward2;

            if (honeySentToTrader > honeyLeftInStorage) {
                // send trader profits from vault
                vault.sendAssets(honeySentToTrader - honeyLeftInStorage, trade.trader);

                // send initial collateral back to trader
                transferFromOrdersToAddress(trade.trader, honeyLeftInStorage);
            } else {
                uint256 amountHoney = honeyLeftInStorage - honeySentToTrader;

                // send trader loss to vault
                transferFromOrdersToAddress(address(this), amountHoney);
                vault.receiveAssets(amountHoney, trade.trader);

                // send remaining initial collateral to back trader
                transferFromOrdersToAddress(trade.trader, honeySentToTrader);
            }
        } else {
            // 4.2 If collateral in vault (opened before update)
            vault.sendAssets(honeySentToTrader, trade.trader);
        }

        // 5. Delete tradeLastUpdated
        delete _tradeLastUpdated[trade.index];
    }

    /// @inheritdoc ISettlement
    function removeLimitLastUpdated(uint256 limitIndex) external onlyEntrypoint {
        delete _tradeLastUpdated[limitIndex];
    }

    /// @inheritdoc ISettlement
    function setTradeLastUpdated(uint256 index, LastUpdated memory _lastUpdated) external onlyEntrypoint {
        _tradeLastUpdated[index] = _lastUpdated;
    }

    function _getTradeValue(
        IOrders.Trade memory trade,
        uint256 currentHoneyPos, // 1e18
        int256 percentProfit, // PRECISION
        ClosingFees memory fees
    )
        internal
        returns (uint256 value)
    {
        // First, calculate the borrowing fee adjusted percent profit.
        int256 netProfitP = percentProfit - int256((fees.borrowFee * 100 * PRECISION) / currentHoneyPos);

        // Then determine the remaining trade value based on all fees.
        (value, fees.rolloverFee, fees.fundingFee) = feesMarkets.getTradeValue(
            trade.pairIndex, trade.index, trade.buy, currentHoneyPos, trade.leverage, netProfitP, fees.closeFee
        );
    }

    /// @notice checks for errors (TP_REACHED, SL_REACHED, EXPOSURE_LIMITS, PRICE_IMPACT, MAX_LEVERAGE) on trade open
    /// @return cancelReason NONE if no errors, otherwise the reason of error
    function getOpenTradeCancelReason(
        IOrders.Trade memory t,
        int64 priceImpactP
    )
        internal
        view
        returns (CancelReason)
    {
        if (t.tp > 0 && (t.buy ? t.openPrice >= t.tp : t.openPrice <= t.tp)) return CancelReason.TP_REACHED;
        if (t.sl > 0 && (t.buy ? t.openPrice <= t.sl : t.openPrice >= t.sl)) return CancelReason.SL_REACHED;
        if (!withinExposureLimits(t.pairIndex, t.buy, t.positionSizeHoney, t.leverage)) {
            return CancelReason.EXPOSURE_LIMITS;
        }
        if (priceImpactP * int256(t.leverage) > feesMarkets.maxNegativePnlOnOpenP()) return CancelReason.PRICE_IMPACT;
        if (!withinMaxLeverage(t.pairIndex, t.leverage)) return CancelReason.MAX_LEVERAGE;

        return CancelReason.NONE;
    }

    function withinMaxLeverage(uint256 pairIndex, uint256 leverage) internal view returns (bool) {
        uint256 pairMaxLev = pairMaxLeverage[pairIndex];
        return pairMaxLev == 0 ? leverage <= getMarkets().pairMaxLeverage(pairIndex) : leverage <= pairMaxLev;
    }

    function withinExposureLimits(
        uint256 pairIndex,
        bool buy,
        uint256 positionSizeHoney,
        uint256 leverage
    )
        internal
        view
        returns (bool)
    {
        uint256 levPositionSizeHoney = positionSizeHoney * leverage;

        return orders.openInterestHoney(pairIndex, buy ? 0 : 1) + levPositionSizeHoney
            <= orders.openInterestHoney(pairIndex, 2) && feesAccrued.withinMaxGroupOi(pairIndex, buy, levPositionSizeHoney);
    }

    function getMarkets() internal view returns (IMarkets) {
        return orders.markets();
    }

    function isInTimeout(IOrders.LimitOrder orderType, uint256 index) internal view returns (bool) {
        if (orderType == IOrders.LimitOrder.LIQ) return false; // Always executable.

        if (orderType == IOrders.LimitOrder.TP) {
            return TradeUtils.isTpInTimeout(address(this), index);
        }

        if (orderType == IOrders.LimitOrder.SL) {
            return TradeUtils.isSlInTimeout(address(this), index);
        }

        return TradeUtils.isLimitInTimeout(address(this), index);
    }

    // Utils (private)
    function transferFromOrdersToAddress(address to, uint256 amountHoney) internal {
        orders.transferHoney(address(orders), to, amountHoney);
    }

    // Public views
    function getAllPairsMaxLeverage() external view returns (uint256[] memory lev) {
        uint256 len = getMarkets().pairsCount();
        lev = new uint256[](len);

        for (uint256 i; i < len;) {
            lev[i] = pairMaxLeverage[i];
            unchecked {
                ++i;
            }
        }
    }

    function tradeLastUpdated(uint256 index) external view returns (LastUpdated memory) {
        return _tradeLastUpdated[index];
    }
}
