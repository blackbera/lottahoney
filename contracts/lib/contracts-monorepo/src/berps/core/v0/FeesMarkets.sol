// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { SafeCastLib } from "solady/src/utils/SafeCastLib.sol";

import { IFeesMarkets } from "../../interfaces/v0/IFeesMarkets.sol";

import { IOrders, StorageUtils } from "./Orders.sol";

import { Utils } from "../../../libraries/Utils.sol";
import { BerpsErrors } from "../../utils/BerpsErrors.sol";

contract FeesMarkets is UUPSUpgradeable, IFeesMarkets {
    using StorageUtils for address;
    using Utils for bytes4;

    // Addresses
    IOrders public orders;
    address public manager;

    // Constant parameters
    int64 constant PRECISION = 1e10; // 10 decimals
    int256 constant LIQ_THRESHOLD_P = 90; // -90% (of collateral)
    int64 constant MAX_NEGATIVE_PNL_ON_OPEN_P = 50e10; // 50% (of collateral)
    uint256 constant MAX_FUNDING_FEE_P = 10_000_000; // ≈ 40% per day
    uint256 constant MAX_ROLLOVER_FEE_P = 25_000_000; // ≈ 100% per day

    // Adjustable parameters
    int64 public maxNegativePnlOnOpenP; // PRECISION (%)

    // Pair parameters
    mapping(uint256 => PairParams) private pairParams;

    // Pair acc funding fees
    mapping(uint256 => PairFundingFees) private pairFundingFees;

    // Pair acc rollover fees
    mapping(uint256 => PairRolloverFees) private pairRolloverFees;

    mapping(uint256 tradeIndex => uint256) private _tradeInitialAccFeeIds;
    TradeInitialAccFees[] private _tradeInitialAccFees;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGov { }

    /// @inheritdoc IFeesMarkets
    function initialize(address _orders, address _manager, int64 _maxNegativePnlOnOpenP) external initializer {
        if (
            _orders == address(0) || _manager == address(0) || _maxNegativePnlOnOpenP == 0
                || _maxNegativePnlOnOpenP > MAX_NEGATIVE_PNL_ON_OPEN_P
        ) BerpsErrors.WrongParams.selector.revertWith();

        orders = IOrders(_orders);
        manager = _manager;
        maxNegativePnlOnOpenP = _maxNegativePnlOnOpenP;
    }

    // Modifiers
    modifier onlyGov() {
        require(msg.sender == orders.gov(), "GOV_ONLY");
        _;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "MANAGER_ONLY");
        _;
    }

    modifier onlySettlement() {
        require(msg.sender == orders.settlement(), "SETTLEMENT_ONLY");
        _;
    }

    // Set manager address
    function setManager(address _manager) external onlyGov {
        require(manager != address(0), "WRONG_PARAMS");
        manager = _manager;

        emit ManagerUpdated(_manager);
    }

    // Set max negative PnL % on trade opening
    function setMaxNegativePnlOnOpenP(int64 value) external onlyManager {
        if (value == 0 || value > MAX_NEGATIVE_PNL_ON_OPEN_P) BerpsErrors.WrongParams.selector.revertWith();
        maxNegativePnlOnOpenP = value;

        emit MaxNegativePnlOnOpenPUpdated(value);
    }

    // Set parameters for pair
    function setPairParams(uint256 pairIndex, PairParams memory value) public onlyManager {
        storeAccRolloverFees(pairIndex);
        storeAccFundingFees(pairIndex);

        pairParams[pairIndex] = value;

        emit PairParamsUpdated(pairIndex, value);
    }

    function setPairParamsArray(uint256[] memory indices, PairParams[] memory values) external onlyManager {
        require(indices.length == values.length, "WRONG_LENGTH");

        for (uint256 i = 0; i < indices.length; i++) {
            setPairParams(indices[i], values[i]);
        }
    }

    // Set one percent depth for pair
    function setOnePercentDepth(uint256 pairIndex, uint256 valueAbove, uint256 valueBelow) public onlyManager {
        PairParams storage p = pairParams[pairIndex];

        p.onePercentDepthAbove = valueAbove;
        p.onePercentDepthBelow = valueBelow;

        emit OnePercentDepthUpdated(pairIndex, valueAbove, valueBelow);
    }

    function setOnePercentDepthArray(
        uint256[] memory indices,
        uint256[] memory valuesAbove,
        uint256[] memory valuesBelow
    )
        external
        onlyManager
    {
        require(indices.length == valuesAbove.length && indices.length == valuesBelow.length, "WRONG_LENGTH");

        for (uint256 i = 0; i < indices.length; i++) {
            setOnePercentDepth(indices[i], valuesAbove[i], valuesBelow[i]);
        }
    }

    // Set rollover fee for pair
    function setRolloverFeePerBlockP(uint256 pairIndex, uint256 value) public onlyManager {
        if (value > MAX_ROLLOVER_FEE_P) BerpsErrors.WrongParams.selector.revertWith();

        storeAccRolloverFees(pairIndex);

        pairParams[pairIndex].rolloverFeePerBlockP = value;

        emit RolloverFeePerBlockPUpdated(pairIndex, value);
    }

    function setRolloverFeePerBlockPArray(uint256[] memory indices, uint256[] memory values) external onlyManager {
        require(indices.length == values.length, "WRONG_LENGTH");

        for (uint256 i = 0; i < indices.length; i++) {
            setRolloverFeePerBlockP(indices[i], values[i]);
        }
    }

    // Set funding fee for pair
    function setFundingFeePerBlockP(uint256 pairIndex, uint256 value) public onlyManager {
        if (value > MAX_FUNDING_FEE_P) BerpsErrors.WrongParams.selector.revertWith();

        storeAccFundingFees(pairIndex);

        pairParams[pairIndex].fundingFeePerBlockP = value;

        emit FundingFeePerBlockPUpdated(pairIndex, value);
    }

    function setFundingFeePerBlockPArray(uint256[] memory indices, uint256[] memory values) external onlyManager {
        require(indices.length == values.length, "WRONG_LENGTH");

        for (uint256 i = 0; i < indices.length; i++) {
            setFundingFeePerBlockP(indices[i], values[i]);
        }
    }

    // Store trade details when opened (acc fee values)
    function storeTradeInitialAccFees(uint256 pairIndex, uint256 tradeIndex, bool long) external onlySettlement {
        storeAccFundingFees(pairIndex);

        TradeInitialAccFees memory t = TradeInitialAccFees(
            tradeIndex,
            getPendingAccRolloverFees(pairIndex),
            long ? pairFundingFees[pairIndex].accPerOiLong : pairFundingFees[pairIndex].accPerOiShort,
            true
        );
        _tradeInitialAccFeeIds[tradeIndex] = _tradeInitialAccFees.length;
        _tradeInitialAccFees.push(t);

        emit TradeInitialAccFeesStored(tradeIndex, t.rollover, t.funding);
    }

    // Acc rollover fees (store right before fee % update)
    function storeAccRolloverFees(uint256 pairIndex) private {
        PairRolloverFees storage r = pairRolloverFees[pairIndex];

        r.accPerCollateral = getPendingAccRolloverFees(pairIndex);
        r.lastUpdateBlock = block.number;

        emit AccRolloverFeesStored(pairIndex, r.accPerCollateral);
    }

    function getPendingAccRolloverFees(uint256 pairIndex) public view returns (uint256) {
        // 1e18 (HONEY)
        PairRolloverFees storage r = pairRolloverFees[pairIndex];

        return r.accPerCollateral
            + ((block.number - r.lastUpdateBlock) * pairParams[pairIndex].rolloverFeePerBlockP * 1e18) / uint64(PRECISION)
                / 100;
    }

    // Acc funding fees (store right before trades opened / closed and fee %
    // update)
    function storeAccFundingFees(uint256 pairIndex) private {
        PairFundingFees storage f = pairFundingFees[pairIndex];

        (f.accPerOiLong, f.accPerOiShort) = getPendingAccFundingFees(pairIndex);
        f.lastUpdateBlock = block.number;

        emit AccFundingFeesStored(pairIndex, f.accPerOiLong, f.accPerOiShort);
    }

    function getPendingAccFundingFees(uint256 pairIndex) public view returns (int256 valueLong, int256 valueShort) {
        PairFundingFees storage f = pairFundingFees[pairIndex];

        valueLong = f.accPerOiLong;
        valueShort = f.accPerOiShort;

        int256 openInterestHoneyLong = int256(orders.openInterestHoney(pairIndex, 0));
        int256 openInterestHoneyShort = int256(orders.openInterestHoney(pairIndex, 1));

        int256 fundingFeesPaidByLongs = (
            (openInterestHoneyLong - openInterestHoneyShort) * int256(block.number - f.lastUpdateBlock)
                * int256(pairParams[pairIndex].fundingFeePerBlockP)
        ) / PRECISION / 100;

        if (openInterestHoneyLong > 0) {
            valueLong += (fundingFeesPaidByLongs * 1e18) / openInterestHoneyLong;
        }

        if (openInterestHoneyShort > 0) {
            valueShort += (fundingFeesPaidByLongs * 1e18 * (-1)) / openInterestHoneyShort;
        }
    }

    /// @inheritdoc IFeesMarkets
    function getTradePriceImpact(
        int64 currentPrice,
        uint256 pairIndex,
        bool long,
        uint256 tradeOpenInterest
    )
        external
        view
        returns (int64 priceImpactP, int64 priceAfterImpact)
    {
        (priceImpactP, priceAfterImpact) = getTradePriceImpactPure(
            currentPrice,
            long,
            orders.openInterestHoney(pairIndex, long ? 0 : 1),
            tradeOpenInterest,
            long ? pairParams[pairIndex].onePercentDepthAbove : pairParams[pairIndex].onePercentDepthBelow
        );
    }

    /// @notice Dynamic price impact value on trade opening.
    /// @param currentPrice The current price of the pair (from oracle) in PRECISION.
    /// @param long Whether the trade is long or short.
    /// @param startOpenInterest The open interest of the pair & direction before this new trade is opened,
    /// in precision of 1e18 (HONEY).
    /// @param tradeOpenInterest The new open interest of the trade caused by this trade in precision of 1e18 (HONEY).
    /// @param onePercentDepth The one percent depth of the pair.
    /// @return priceImpactP The price impact of the trade in PRECISION %.
    /// @return priceAfterImpact The price after the trade impact in PRECISION, should be used as trade's opening
    /// price.
    function getTradePriceImpactPure(
        int64 currentPrice,
        bool long,
        uint256 startOpenInterest,
        uint256 tradeOpenInterest,
        uint256 onePercentDepth
    )
        public
        pure
        returns (int64 priceImpactP, int64 priceAfterImpact)
    {
        if (onePercentDepth == 0) {
            return (0, currentPrice);
        }

        priceImpactP =
            int64(int256(((startOpenInterest + tradeOpenInterest / 2) * uint64(PRECISION)) / 1e18 / onePercentDepth));

        int64 priceImpact = (priceImpactP * currentPrice) / PRECISION / 100;

        priceAfterImpact = long ? currentPrice + priceImpact : currentPrice - priceImpact;
    }

    // Rollover fee value
    function getTradeRolloverFee(
        uint256 pairIndex,
        uint256 tradeIndex,
        uint256 collateral // 1e18 (HONEY)
    )
        public
        view
        returns (
            uint256 // 1e18 (HONEY)
        )
    {
        TradeInitialAccFees memory t = _tradeInitialAccFees[_tradeInitialAccFeeIds[tradeIndex]];

        if (!t.openedAfterUpdate) {
            return 0;
        }

        return getTradeRolloverFeePure(t.rollover, getPendingAccRolloverFees(pairIndex), collateral);
    }

    function getTradeRolloverFeePure(
        uint256 accRolloverFeesPerCollateral,
        uint256 endAccRolloverFeesPerCollateral,
        uint256 collateral // 1e18 (HONEY)
    )
        public
        pure
        returns (
            uint256 // 1e18 (HONEY)
        )
    {
        return ((endAccRolloverFeesPerCollateral - accRolloverFeesPerCollateral) * collateral) / 1e18;
    }

    // Funding fee value
    function getTradeFundingFee(
        uint256 pairIndex,
        uint256 tradeIndex,
        bool long,
        uint256 collateral, // 1e18 (HONEY)
        uint256 leverage
    )
        public
        view
        returns (
            int256 // 1e18 (HONEY) | Positive => Fee, Negative => Reward
        )
    {
        TradeInitialAccFees memory t = _tradeInitialAccFees[_tradeInitialAccFeeIds[tradeIndex]];

        if (!t.openedAfterUpdate) {
            return 0;
        }

        (int256 pendingLong, int256 pendingShort) = getPendingAccFundingFees(pairIndex);

        return getTradeFundingFeePure(t.funding, long ? pendingLong : pendingShort, collateral, leverage);
    }

    function getTradeFundingFeePure(
        int256 accFundingFeesPerOi,
        int256 endAccFundingFeesPerOi,
        uint256 collateral, // 1e18 (HONEY)
        uint256 leverage
    )
        public
        pure
        returns (
            int256 // 1e18 (HONEY) | Positive => Fee, Negative => Reward
        )
    {
        return ((endAccFundingFeesPerOi - accFundingFeesPerOi) * int256(collateral) * int256(leverage)) / 1e18;
    }

    // Liquidation price value after rollover and funding fees
    function getTradeLiquidationPrice(
        uint256 pairIndex,
        uint256 index,
        int64 openPrice, // PRECISION
        bool long,
        uint256 collateral, // 1e18 (HONEY)
        uint256 leverage
    )
        external
        view
        returns (int64)
    {
        // PRECISION
        return getTradeLiquidationPricePure(
            openPrice,
            long,
            collateral,
            leverage,
            getTradeRolloverFee(pairIndex, index, collateral),
            getTradeFundingFee(pairIndex, index, long, collateral, leverage)
        );
    }

    function getTradeLiquidationPricePure(
        int64 openPrice, // PRECISION
        bool long,
        uint256 collateral, // 1e18 (HONEY)
        uint256 leverage,
        uint256 rolloverFee, // 1e18 (HONEY)
        int256 fundingFee // 1e18 (HONEY)
    )
        public
        pure
        returns (int64)
    {
        // PRECISION
        int64 liqPriceDistance = SafeCastLib.toInt64(
            (int256(openPrice) * ((int256(collateral) * LIQ_THRESHOLD_P / 100) - int256(rolloverFee) - fundingFee))
                / int256(collateral) / int256(leverage)
        );

        int64 liqPrice = long ? openPrice - liqPriceDistance : openPrice + liqPriceDistance;

        return liqPrice > 0 ? liqPrice : int64(0);
    }

    // Honey (1e18) sent to trader after PnL and fees (1e18) on closing of trade
    function getTradeValue(
        uint256 pairIndex,
        uint256 tradeIndex,
        bool long,
        uint256 collateral, // 1e18 (HONEY)
        uint256 leverage,
        int256 percentProfit, // PRECISION (%)
        uint256 closingFee // 1e18 (HONEY)
    )
        external
        onlySettlement
        returns (uint256 value, uint256 r, int256 f)
    {
        storeAccFundingFees(pairIndex);

        r = getTradeRolloverFee(pairIndex, tradeIndex, collateral);
        f = getTradeFundingFee(pairIndex, tradeIndex, long, collateral, leverage);
        value = getTradeValuePure(collateral, percentProfit, r, f, closingFee);

        // Update trade fees
        uint256 id = _tradeInitialAccFeeIds[tradeIndex];
        TradeInitialAccFees memory replaceF = _tradeInitialAccFees[_tradeInitialAccFees.length - 1];
        _tradeInitialAccFees[id] = replaceF;
        _tradeInitialAccFeeIds[replaceF.tradeIndex] = id;

        delete _tradeInitialAccFeeIds[tradeIndex];
        _tradeInitialAccFees.pop();
    }

    function getTradeValuePure(
        uint256 collateral, // 1e18 (HONEY)
        int256 percentProfit, // PRECISION (%)
        uint256 rolloverFee, // 1e18 (HONEY)
        int256 fundingFee, // 1e18 (HONEY)
        uint256 closingFee // 1e18 (HONEY)
    )
        public
        pure
        returns (uint256)
    {
        // 1e18 (HONEY)
        int256 value = int256(collateral) + (int256(collateral) * percentProfit) / int64(PRECISION) / 100
            - int256(rolloverFee) - fundingFee;

        if (value <= (int256(collateral) * int256(100 - LIQ_THRESHOLD_P)) / 100) {
            return 0;
        }

        value -= int256(closingFee);

        return value > 0 ? uint256(value) : 0;
    }

    // Useful getters
    function getPair(uint256 pairIndex)
        external
        view
        returns (PairParams memory, PairRolloverFees memory, PairFundingFees memory)
    {
        return (pairParams[pairIndex], pairRolloverFees[pairIndex], pairFundingFees[pairIndex]);
    }

    function getAllPairs()
        external
        view
        returns (PairParams[] memory, PairRolloverFees[] memory, PairFundingFees[] memory)
    {
        uint256 len = orders.markets().pairsCount();

        PairParams[] memory p = new PairParams[](len);
        PairRolloverFees[] memory r = new PairRolloverFees[](len);
        PairFundingFees[] memory f = new PairFundingFees[](len);

        for (uint256 i = 0; i < len;) {
            p[i] = pairParams[i];
            r[i] = pairRolloverFees[i];
            f[i] = pairFundingFees[i];
            unchecked {
                ++i;
            }
        }

        return (p, r, f);
    }

    function getOnePercentDepthAbove(uint256 pairIndex) external view returns (uint256) {
        return pairParams[pairIndex].onePercentDepthAbove;
    }

    function getOnePercentDepthBelow(uint256 pairIndex) external view returns (uint256) {
        return pairParams[pairIndex].onePercentDepthBelow;
    }

    function getRolloverFeePerBlockP(uint256 pairIndex) external view returns (uint256) {
        return pairParams[pairIndex].rolloverFeePerBlockP;
    }

    function getFundingFeePerBlockP(uint256 pairIndex) external view returns (uint256) {
        return pairParams[pairIndex].fundingFeePerBlockP;
    }

    function getAccRolloverFees(uint256 pairIndex) external view returns (uint256) {
        return pairRolloverFees[pairIndex].accPerCollateral;
    }

    function getAccRolloverFeesUpdateBlock(uint256 pairIndex) external view returns (uint256) {
        return pairRolloverFees[pairIndex].lastUpdateBlock;
    }

    function getAccFundingFeesLong(uint256 pairIndex) external view returns (int256) {
        return pairFundingFees[pairIndex].accPerOiLong;
    }

    function getAccFundingFeesShort(uint256 pairIndex) external view returns (int256) {
        return pairFundingFees[pairIndex].accPerOiShort;
    }

    function getAccFundingFeesUpdateBlock(uint256 pairIndex) external view returns (uint256) {
        return pairFundingFees[pairIndex].lastUpdateBlock;
    }

    function tradeInitialAccFees(uint256 tradeIndex) external view override returns (TradeInitialAccFees memory fee) {
        uint256 id = _tradeInitialAccFeeIds[tradeIndex];
        if (id < _tradeInitialAccFees.length) fee = _tradeInitialAccFees[id];
    }

    function getTradeInitialAccFees(
        uint256 offset,
        uint256 count
    )
        external
        view
        override
        returns (TradeInitialAccFees[] memory fees)
    {
        // If the count requested is 0 or the offset is beyond the array length, return an empty array.
        if (count == 0 || offset >= _tradeInitialAccFees.length) return new TradeInitialAccFees[](0);

        // Calculate the size of the array to return: smaller of `count` or `_tradeInitialAccFees.length - offset`.
        uint256 outputSize =
            (offset + count > _tradeInitialAccFees.length) ? _tradeInitialAccFees.length - offset : count;

        // Initialize the array of results and populate.
        fees = new TradeInitialAccFees[](outputSize);
        unchecked {
            for (uint256 i = 0; i < outputSize; ++i) {
                fees[i] = _tradeInitialAccFees[offset + i];
            }
        }
    }
}
