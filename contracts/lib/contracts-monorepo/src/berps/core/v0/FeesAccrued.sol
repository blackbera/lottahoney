// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "solady/src/utils/SafeCastLib.sol";

import { Utils } from "../../../libraries/Utils.sol";
import { BerpsErrors } from "../../utils/BerpsErrors.sol";

import { IFeesAccrued } from "../../interfaces/v0/IFeesAccrued.sol";
import { IFeesMarkets } from "../../interfaces/v0/IFeesMarkets.sol";

import { IVault, IOrders, StorageUtils } from "./Orders.sol";

contract FeesAccrued is UUPSUpgradeable, IFeesAccrued {
    using StorageUtils for address;
    using FixedPointMathLib for uint256;
    using SafeCastLib for uint256;
    using Utils for bytes4;

    // Constants
    uint256 constant P_1 = 1e10;
    uint256 constant P_2 = 1e18; // used for HONEY
    uint256 constant P_3 = 1e40;
    uint256 constant SECONDS_PER_YEAR = 365.25 * 24 * 60 * 60 seconds;
    uint256 constant MIN_BASE_BORROW_APR = P_1; // 1% Base Borrow APR

    // Addresses
    IOrders public orders;
    IFeesMarkets public feesMarkets;

    // State
    mapping(uint16 => Group) public groups;
    mapping(uint256 => Pair) public pairs;
    mapping(uint256 tradeIndex => uint256) private initialAccFeeIds;
    InitialAccFees[] private initialAccFees;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGov { }

    /// @inheritdoc IFeesAccrued
    function initialize(address _orders, address _feesMarkets) external initializer {
        if (_orders == address(0) || _feesMarkets == address(0)) BerpsErrors.WrongParams.selector.revertWith();

        orders = IOrders(_orders);
        feesMarkets = IFeesMarkets(_feesMarkets);
    }

    // Modifiers
    modifier onlyGov() {
        if (msg.sender != orders.gov()) BerpsErrors.Unauthorized.selector.revertWith();
        _;
    }

    modifier onlyManager() {
        if (msg.sender != feesMarkets.manager()) BerpsErrors.Unauthorized.selector.revertWith();
        _;
    }

    modifier onlySettlement() {
        if (msg.sender != orders.settlement()) BerpsErrors.Unauthorized.selector.revertWith();
        _;
    }

    // Manage pair params
    function setPairParams(uint256 pairIndex, PairParams calldata value) external onlyManager {
        _setPairParams(pairIndex, value);
    }

    function setPairParamsArray(uint256[] calldata indices, PairParams[] calldata values) external onlyManager {
        uint256 len = indices.length;
        if (len != values.length) BerpsErrors.WrongParams.selector.revertWith();

        for (uint256 i; i < len;) {
            _setPairParams(indices[i], values[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _setPairParams(uint256 pairIndex, PairParams calldata value) private {
        if (value.baseBorrowAPR < MIN_BASE_BORROW_APR) BerpsErrors.WrongParams.selector.revertWith();

        _setPairPendingAccFees(pairIndex);

        Pair storage p = pairs[pairIndex];
        uint16 prevGroupIndex = getPairGroupIndex(pairIndex);
        if (value.groupIndex != prevGroupIndex) {
            _setGroupPendingAccFees(prevGroupIndex);
            _setGroupPendingAccFees(value.groupIndex);

            (uint256 oiLong, uint256 oiShort,) = getPairOpenInterest(pairIndex);

            // Only remove OI from old group if old group is not 0
            _setGroupOi(prevGroupIndex, true, false, oiLong);
            _setGroupOi(prevGroupIndex, false, false, oiShort);

            // Add OI to new group if it's not group 0 (even if old group is 0)
            // So when we assign a pair to a group, it takes into account its OI
            // And group 0 OI will always be 0 but it doesn't matter since it's
            // not used
            _setGroupOi(value.groupIndex, true, true, oiLong);
            _setGroupOi(value.groupIndex, false, true, oiShort);

            Group memory newGroup = groups[value.groupIndex];
            Group memory prevGroup = groups[prevGroupIndex];

            p.groups.push(
                PairGroup(
                    value.groupIndex,
                    uint48(block.timestamp), // rawdogging it: 281,474,976,710,655 seconds.
                    newGroup.accFeeLong,
                    newGroup.accFeeShort,
                    prevGroup.accFeeLong,
                    prevGroup.accFeeShort,
                    p.accFeeLong,
                    p.accFeeShort,
                    0 // placeholder
                )
            );

            emit PairGroupUpdated(pairIndex, prevGroupIndex, value.groupIndex);
        }

        p.feePerSecond = value.baseBorrowAPR.divUp(SECONDS_PER_YEAR).toUint32();
        emit PairParamsUpdated(pairIndex, value.groupIndex, p.feePerSecond);
    }

    // Manage group params
    function setGroupParams(uint16 groupIndex, GroupParams calldata value) external onlyManager {
        _setGroupParams(groupIndex, value);
    }

    function setGroupParamsArray(uint16[] calldata indices, GroupParams[] calldata values) external onlyManager {
        if (indices.length != values.length) BerpsErrors.WrongParams.selector.revertWith();

        for (uint256 i; i < indices.length;) {
            _setGroupParams(indices[i], values[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _setGroupParams(uint16 groupIndex, GroupParams calldata value) private {
        if (groupIndex == 0) BerpsErrors.WrongParams.selector.revertWith();
        if (value.baseBorrowAPR < MIN_BASE_BORROW_APR) BerpsErrors.WrongParams.selector.revertWith();

        _setGroupPendingAccFees(groupIndex);
        Group storage g = groups[groupIndex];
        uint32 feePerSecond = value.baseBorrowAPR.divUp(SECONDS_PER_YEAR).toUint32();
        (g.feePerSecond, g.maxOi) = (feePerSecond, value.maxOi);

        emit GroupUpdated(groupIndex, feePerSecond, value.maxOi);
    }

    // Group OI setter
    function _setGroupOi(
        uint16 groupIndex,
        bool long,
        bool increase,
        uint256 amount // 1e18
    )
        private
    {
        Group storage group = groups[groupIndex];
        uint112 amountFinal = 0;

        if (groupIndex > 0) {
            amountFinal = ((amount * P_1) / P_2).toUint112(); // 1e10

            if (long) {
                group.oiLong = increase
                    ? group.oiLong + amountFinal
                    : group.oiLong - (group.oiLong > amountFinal ? amountFinal : group.oiLong);
            } else {
                group.oiShort = increase
                    ? group.oiShort + amountFinal
                    : group.oiShort - (group.oiShort > amountFinal ? amountFinal : group.oiShort);
            }
        }

        emit GroupOiUpdated(groupIndex, long, increase, amountFinal, group.oiLong, group.oiShort);
    }

    // Acc fees getters for pairs and groups
    function getPendingAccFees(
        uint64 accFeeLong, // 1e10 (%)
        uint64 accFeeShort, // 1e10 (%)
        uint256 oiLong, // 1e18
        uint256 oiShort, // 1e18
        uint32 feePerSecond, // 1e10
        uint256 currentTime,
        uint256 accLastUpdatedTime,
        uint256 vaultMarketCap // 1e18
    )
        public
        pure
        returns (uint64 newAccFeeLong, uint64 newAccFeeShort)
    {
        if (currentTime <= accLastUpdatedTime) return (accFeeLong, accFeeShort);

        // Do not use `getCurrentFeeRate` here to calculate `delta` to avoid dividing before multiplying.
        int256 delta = (
            (int256(oiLong) - int256(oiShort)) * int256(uint256(feePerSecond))
                * int256(currentTime - accLastUpdatedTime)
        ) / int256(vaultMarketCap); // 1e10 (%)
        uint256 deltaUint = 0;

        if (delta < 0) {
            deltaUint = uint256(delta * (-1));
            newAccFeeLong = accFeeLong;
            newAccFeeShort = accFeeShort + deltaUint.toUint64();
        } else {
            deltaUint = uint256(delta);
            newAccFeeLong = accFeeLong + deltaUint.toUint64();
            newAccFeeShort = accFeeShort;
        }
    }

    /// @dev Gets the rate of fees per second for a pair or group, based on its net OI and the vault's market cap.
    /// @return feeRate The rate of fees per second for the pair or group (precision of 1e10).
    /// @return long Whether the fee rate is for long side or short side (the other side is 0).
    function getCurrentFeeRate(
        uint256 oiLong, // 1e18
        uint256 oiShort, // 1e18
        uint32 feePerSecond, // 1e10
        uint256 vaultMarketCap // 1e18
    )
        internal
        pure
        returns (uint256, bool)
    {
        int256 feeRateInt =
            ((int256(oiLong) - int256(oiShort)) * int256(uint256(feePerSecond))) / int256(vaultMarketCap);

        return (FixedPointMathLib.abs(feeRateInt), feeRateInt > 0);
    }

    function getPairGroupAccFeesDeltasNoTrade(
        uint256 i,
        PairGroup[] memory pairGroups,
        uint256 pairIndex,
        bool long,
        uint256 currentTime
    )
        public
        view
        returns (uint64 deltaGroup, uint64 deltaPair)
    {
        PairGroup memory group = pairGroups[i];

        // TODO: handle pairGroups.length == 0
        if (i == pairGroups.length - 1) {
            // Last active group
            deltaGroup = getGroupPendingAccFee(group.groupIndex, currentTime, long);
            deltaPair = getPairPendingAccFee(pairIndex, currentTime, long);
        } else {
            // Previous groups
            PairGroup memory nextGroup = pairGroups[i + 1];
            deltaGroup = long ? nextGroup.prevGroupAccFeeLong : nextGroup.prevGroupAccFeeShort;
            deltaPair = long ? nextGroup.pairAccFeeLong : nextGroup.pairAccFeeShort;
        }

        deltaGroup -= (long ? group.initialAccFeeLong : group.initialAccFeeShort);
        deltaPair -= (long ? group.pairAccFeeLong : group.pairAccFeeShort);
    }

    function getPairGroupAccFeesDeltas(
        uint256 i,
        PairGroup[] memory pairGroups,
        InitialAccFees memory initialFees,
        uint256 pairIndex,
        bool long,
        uint256 currentTime
    )
        public
        view
        returns (uint64 deltaGroup, uint64 deltaPair, bool beforeTradeOpen)
    {
        PairGroup memory group = pairGroups[i];

        beforeTradeOpen = group.timestamp < initialFees.timestamp;

        // TODO: handle pairGroups.length == 0
        if (i == pairGroups.length - 1) {
            // Last active group
            deltaGroup = getGroupPendingAccFee(group.groupIndex, currentTime, long);
            deltaPair = getPairPendingAccFee(pairIndex, currentTime, long);
        } else {
            // Previous groups
            PairGroup memory nextGroup = pairGroups[i + 1];

            // If it's not the first group to be before the trade was opened then fee is 0
            if (beforeTradeOpen && nextGroup.timestamp <= initialFees.timestamp) {
                return (0, 0, beforeTradeOpen);
            }

            deltaGroup = long ? nextGroup.prevGroupAccFeeLong : nextGroup.prevGroupAccFeeShort;
            deltaPair = long ? nextGroup.pairAccFeeLong : nextGroup.pairAccFeeShort;
        }

        if (beforeTradeOpen) {
            deltaGroup -= initialFees.accGroupFee;
            deltaPair -= initialFees.accPairFee;
        } else {
            deltaGroup -= (long ? group.initialAccFeeLong : group.initialAccFeeShort);
            deltaPair -= (long ? group.pairAccFeeLong : group.pairAccFeeShort);
        }
    }

    // Pair acc fees helpers
    function getPairPendingAccFees(
        uint256 pairIndex,
        uint256 currentTime
    )
        public
        view
        returns (uint64 accFeeLong, uint64 accFeeShort)
    {
        uint256 vaultMarketCap = getPairWeightedVaultMarketCapSinceLastUpdate(pairIndex, currentTime);
        uint32 feePerSecond;
        uint48 accLastUpdatedTime;
        {
            Pair storage pair = pairs[pairIndex];
            (feePerSecond, accFeeLong, accFeeShort, accLastUpdatedTime) =
                (pair.feePerSecond, pair.accFeeLong, pair.accFeeShort, pair.accLastUpdatedTime);
        }

        (uint256 pairOiLong, uint256 pairOiShort,) = getPairOpenInterest(pairIndex);

        (accFeeLong, accFeeShort) = getPendingAccFees(
            accFeeLong,
            accFeeShort,
            pairOiLong,
            pairOiShort,
            feePerSecond,
            currentTime,
            accLastUpdatedTime,
            vaultMarketCap
        );
    }

    /// @inheritdoc IFeesAccrued
    function getPairsCurrentAPR(uint256[] calldata indices)
        external
        view
        returns (uint256[] memory borrowAPRLong, uint256[] memory borrowAPRShort)
    {
        borrowAPRLong = new uint256[](indices.length);
        borrowAPRShort = new uint256[](indices.length);

        for (uint256 i = 0; i < indices.length;) {
            uint256 pairIndex = indices[i];
            uint256 vaultMarketCap = getPairWeightedVaultMarketCapSinceLastUpdate(pairIndex, block.timestamp);
            (uint256 pairOiLong, uint256 pairOiShort,) = getPairOpenInterest(pairIndex);
            Pair storage pair = pairs[pairIndex];

            // Get the latest fee rate per second, then multiply up for APR.
            (uint256 feeRate, bool long) =
                getCurrentFeeRate(pairOiLong, pairOiShort, pair.feePerSecond, vaultMarketCap);
            if (long) {
                borrowAPRLong[i] = feeRate * SECONDS_PER_YEAR;
            } else {
                borrowAPRShort[i] = feeRate * SECONDS_PER_YEAR;
            }

            unchecked {
                ++i;
            }
        }
    }

    function getPairPendingAccFee(
        uint256 pairIndex,
        uint256 currentTime,
        bool long
    )
        public
        view
        returns (uint64 accFee)
    {
        (uint64 accFeeLong, uint64 accFeeShort) = getPairPendingAccFees(pairIndex, currentTime);
        return long ? accFeeLong : accFeeShort;
    }

    function _setPairPendingAccFees(uint256 pairIndex) private returns (uint64 accFeeLong, uint64 accFeeShort) {
        (accFeeLong, accFeeShort) = getPairPendingAccFees(pairIndex, block.timestamp);
        uint256 lastAccTimeWeightedMarketCap = getPendingAccTimeWeightedMarketCap(block.timestamp);

        Pair storage pair = pairs[pairIndex];

        // rawdogging it: 281,474,976,710,655 seconds.
        (pair.accFeeLong, pair.accFeeShort, pair.accLastUpdatedTime, pair.lastAccTimeWeightedMarketCap) =
            (accFeeLong, accFeeShort, uint48(block.timestamp), lastAccTimeWeightedMarketCap);

        emit PairAccFeesUpdated(pairIndex, block.timestamp, accFeeLong, accFeeShort, lastAccTimeWeightedMarketCap);
    }

    // Group acc fees helpers
    function getGroupPendingAccFees(
        uint16 groupIndex,
        uint256 currentTime
    )
        public
        view
        returns (uint64 accFeeLong, uint64 accFeeShort)
    {
        uint256 vaultMarketCap = getGroupWeightedVaultMarketCapSinceLastUpdate(groupIndex, currentTime);
        Group storage group = groups[groupIndex];

        (accFeeLong, accFeeShort) = getPendingAccFees(
            group.accFeeLong,
            group.accFeeShort,
            (uint256(group.oiLong) * P_2) / P_1,
            (uint256(group.oiShort) * P_2) / P_1,
            group.feePerSecond,
            currentTime,
            group.accLastUpdatedTime,
            vaultMarketCap
        );
    }

    /// @inheritdoc IFeesAccrued
    function getGroupsCurrentAPR(uint16[] calldata indices)
        external
        view
        returns (uint256[] memory borrowAPRLong, uint256[] memory borrowAPRShort)
    {
        borrowAPRLong = new uint256[](indices.length);
        borrowAPRShort = new uint256[](indices.length);

        for (uint256 i = 0; i < indices.length;) {
            uint16 groupIndex = indices[i];
            uint256 vaultMarketCap = getGroupWeightedVaultMarketCapSinceLastUpdate(groupIndex, block.timestamp);
            Group storage group = groups[groupIndex];

            // Get the latest fee rate per second, then multiply up for APR.
            (uint256 feeRate, bool long) = getCurrentFeeRate(
                (uint256(group.oiLong) * P_2) / P_1,
                (uint256(group.oiShort) * P_2) / P_1,
                group.feePerSecond,
                vaultMarketCap
            );
            if (long) {
                borrowAPRLong[i] = feeRate * SECONDS_PER_YEAR;
            } else {
                borrowAPRShort[i] = feeRate * SECONDS_PER_YEAR;
            }

            unchecked {
                ++i;
            }
        }
    }

    function getGroupPendingAccFee(
        uint16 groupIndex,
        uint256 currentTime,
        bool long
    )
        public
        view
        returns (uint64 accFee)
    {
        (uint64 accFeeLong, uint64 accFeeShort) = getGroupPendingAccFees(groupIndex, currentTime);
        return long ? accFeeLong : accFeeShort;
    }

    function _setGroupPendingAccFees(uint16 groupIndex) private returns (uint64 accFeeLong, uint64 accFeeShort) {
        (accFeeLong, accFeeShort) = getGroupPendingAccFees(groupIndex, block.timestamp);
        uint256 lastAccTimeWeightedMarketCap = getPendingAccTimeWeightedMarketCap(block.timestamp);

        Group storage group = groups[groupIndex];

        // rawdogging it: 281,474,976,710,655 seconds.
        (group.accFeeLong, group.accFeeShort, group.accLastUpdatedTime, group.lastAccTimeWeightedMarketCap) =
            (accFeeLong, accFeeShort, uint48(block.timestamp), lastAccTimeWeightedMarketCap);

        emit GroupAccFeesUpdated(groupIndex, block.timestamp, accFeeLong, accFeeShort, lastAccTimeWeightedMarketCap);
    }

    // Interaction with settlement
    function handleTradeAction(
        uint256 pairIndex,
        uint256 tradeIndex,
        uint256 positionSizeHoney, // 1e18 (collateral * leverage)
        bool open,
        bool long
    )
        external
        override
        onlySettlement
    {
        uint16 groupIndex = getPairGroupIndex(pairIndex);

        (uint64 pairAccFeeLong, uint64 pairAccFeeShort) = _setPairPendingAccFees(pairIndex);
        (uint64 groupAccFeeLong, uint64 groupAccFeeShort) = _setGroupPendingAccFees(groupIndex);

        _setGroupOi(groupIndex, long, open, positionSizeHoney);

        if (open) {
            InitialAccFees memory initialFees = InitialAccFees(
                tradeIndex,
                long ? pairAccFeeLong : pairAccFeeShort,
                long ? groupAccFeeLong : groupAccFeeShort,
                uint48(block.timestamp), // rawdogging it: 281,474,976,710,655 seconds.
                0 // placeholder
            );
            initialAccFeeIds[tradeIndex] = initialAccFees.length;
            initialAccFees.push(initialFees);

            emit TradeInitialAccFeesStored(tradeIndex, initialFees.accPairFee, initialFees.accGroupFee);
        } else {
            uint256 id = initialAccFeeIds[tradeIndex];
            InitialAccFees memory replaceF = initialAccFees[initialAccFees.length - 1];
            initialAccFees[id] = replaceF;
            initialAccFeeIds[replaceF.tradeIndex] = id;

            delete initialAccFeeIds[tradeIndex];
            initialAccFees.pop();
        }
    }

    // Important trade getters

    /// @return fee the borrow fee in HONEY for a trade that is closing in the current block (precision of 1e18)
    function getTradeBorrowingFee(BorrowingFeeInput memory input) public view returns (uint256 fee) {
        InitialAccFees memory initialFees = initialAccFees[initialAccFeeIds[input.tradeIndex]];
        if (initialFees.timestamp == 0) BerpsErrors.NoTrade.selector.revertWith();

        PairGroup[] memory pairGroups = pairs[input.pairIndex].groups;
        PairGroup memory firstPairGroup;
        if (pairGroups.length > 0) {
            firstPairGroup = pairGroups[0];
        }

        // If pair has had no group after trade was opened, initialize with pair borrowing fee
        if (pairGroups.length == 0 || firstPairGroup.timestamp > initialFees.timestamp) {
            fee = (
                (
                    pairGroups.length == 0
                        ? getPairPendingAccFee(input.pairIndex, block.timestamp, input.long)
                        : (input.long ? firstPairGroup.pairAccFeeLong : firstPairGroup.pairAccFeeShort)
                ) - initialFees.accPairFee
            );
        }

        // Sum of max(pair fee, group fee) for all groups the pair was in while trade was open
        for (uint256 i = pairGroups.length; i > 0;) {
            (uint64 deltaGroup, uint64 deltaPair, bool beforeTradeOpen) =
                getPairGroupAccFeesDeltas(i - 1, pairGroups, initialFees, input.pairIndex, input.long, block.timestamp);

            fee += (deltaGroup > deltaPair ? deltaGroup : deltaPair);

            // Exit loop at first group before trade was open
            if (beforeTradeOpen) break;
            unchecked {
                --i;
            }
        }

        fee = (input.collateral * input.leverage * fee) / P_1 / 100;
    }

    /// @inheritdoc IFeesAccrued
    function getTradeLiquidationPrice(LiqPriceInput calldata input)
        external
        view
        returns (int64 liqPrice, uint256 borrowFee)
    {
        borrowFee = getTradeBorrowingFee(
            BorrowingFeeInput(input.pairIndex, input.tradeIndex, input.long, input.collateral, input.leverage)
        );
        liqPrice = feesMarkets.getTradeLiquidationPricePure(
            input.openPrice,
            input.long,
            input.collateral,
            input.leverage,
            feesMarkets.getTradeRolloverFee(input.pairIndex, input.tradeIndex, input.collateral) + borrowFee,
            feesMarkets.getTradeFundingFee(
                input.pairIndex, input.tradeIndex, input.long, input.collateral, input.leverage
            )
        );
    }

    // Public getters

    /// @inheritdoc IFeesAccrued
    function getTradesLiquidationPrices(uint256[] calldata tradeIndices)
        external
        view
        returns (int64[] memory liqPrices, uint256[] memory borrowFees)
    {
        liqPrices = new int64[](tradeIndices.length);
        borrowFees = new uint256[](tradeIndices.length);

        for (uint256 i = 0; i < tradeIndices.length;) {
            IOrders.Trade memory t = orders.getOpenTrade(tradeIndices[i]);
            if (t.leverage == 0) continue;
            borrowFees[i] =
                getTradeBorrowingFee(BorrowingFeeInput(t.pairIndex, t.index, t.buy, t.positionSizeHoney, t.leverage));
            liqPrices[i] = feesMarkets.getTradeLiquidationPricePure(
                t.openPrice,
                t.buy,
                t.positionSizeHoney,
                t.leverage,
                feesMarkets.getTradeRolloverFee(t.pairIndex, t.index, t.positionSizeHoney) + borrowFees[i],
                feesMarkets.getTradeFundingFee(t.pairIndex, t.index, t.buy, t.positionSizeHoney, t.leverage)
            );
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Gets the current open interest for the pair
    /// @return longOI the open interest for the long side
    /// @return shortOI the open interest for the short side
    /// @return maxOI the maximum open interest allowed for the pair
    function getPairOpenInterest(uint256 pairIndex) public view returns (uint256, uint256, uint256) {
        return (
            orders.openInterestHoney(pairIndex, 0),
            orders.openInterestHoney(pairIndex, 1),
            orders.openInterestHoney(pairIndex, 2)
        );
    }

    /// @notice Gets the current open interest for the given pairs
    /// @return longOIs the open interest for the long sides
    /// @return shortOIs the open interest for the short sides
    /// @return maxOIs the maximum open interest allowed for the pairs
    function getPairsOpenInterest(uint256[] calldata indices)
        external
        view
        returns (uint256[] memory longOIs, uint256[] memory shortOIs, uint256[] memory maxOIs)
    {
        longOIs = new uint256[](indices.length);
        shortOIs = new uint256[](indices.length);
        maxOIs = new uint256[](indices.length);

        for (uint256 i; i < indices.length;) {
            longOIs[i] = orders.openInterestHoney(i, 0);
            shortOIs[i] = orders.openInterestHoney(i, 1);
            maxOIs[i] = orders.openInterestHoney(i, 2);
            unchecked {
                ++i;
            }
        }
    }

    function getPairGroupIndex(uint256 pairIndex) public view returns (uint16 groupIndex) {
        PairGroup[] storage pairGroups = pairs[pairIndex].groups;
        uint256 len = pairGroups.length;
        unchecked {
            groupIndex = len == 0 ? 0 : pairGroups[len - 1].groupIndex;
        }
    }

    function getPendingAccTimeWeightedMarketCap(uint256 currentTime) public view returns (uint256) {
        return orders.vault().getPendingAccTimeWeightedMarketCap(currentTime);
    }

    function getGroupWeightedVaultMarketCapSinceLastUpdate(
        uint16 groupIndex,
        uint256 currentTime
    )
        public
        view
        returns (uint256)
    {
        Group storage g = groups[groupIndex];
        (uint48 accLastUpdatedTime, uint256 lastAccTimeWeightedMarketCap) =
            (g.accLastUpdatedTime, g.lastAccTimeWeightedMarketCap);
        return getWeightedVaultMarketCap(
            getPendingAccTimeWeightedMarketCap(currentTime),
            lastAccTimeWeightedMarketCap,
            currentTime - accLastUpdatedTime
        );
    }

    function getPairWeightedVaultMarketCapSinceLastUpdate(
        uint256 pairIndex,
        uint256 currentTime
    )
        public
        view
        returns (uint256)
    {
        Pair storage p = pairs[pairIndex];
        (uint48 accLastUpdatedTime, uint256 lastAccTimeWeightedMarketCap) =
            (p.accLastUpdatedTime, p.lastAccTimeWeightedMarketCap);
        return getWeightedVaultMarketCap(
            getPendingAccTimeWeightedMarketCap(currentTime),
            lastAccTimeWeightedMarketCap,
            currentTime - accLastUpdatedTime
        );
    }

    /// @return timeWeightedVaultMarketCap in HONEY with a precision of 1e18
    function getWeightedVaultMarketCap(
        uint256 accTimeWeightedMarketCap,
        uint256 lastAccTimeWeightedMarketCap,
        uint256 timeDelta
    )
        public
        pure
        returns (uint256)
    {
        // return 1 in case timeDelta is 0 since acc borrowing fees delta will be 0 anyway, and 0/1 = 0
        return timeDelta > 0 ? (timeDelta * P_3) / (accTimeWeightedMarketCap - lastAccTimeWeightedMarketCap) : 1;
    }

    // External getters
    function withinMaxGroupOi(
        uint256 pairIndex,
        bool long,
        uint256 positionSizeHoney // 1e18
    )
        external
        view
        returns (bool)
    {
        Group storage g = groups[getPairGroupIndex(pairIndex)];
        (uint112 oiLong, uint112 oiShort, uint80 maxOi) = (g.oiLong, g.oiShort, g.maxOi);
        return (maxOi == 0) || ((long ? oiLong : oiShort) + (positionSizeHoney * P_1) / P_2 <= maxOi);
    }

    function getAllPairs() external view returns (Pair[] memory p) {
        uint256 len = orders.markets().pairsCount();
        p = new Pair[](len);

        for (uint256 i = 0; i < len;) {
            p[i] = pairs[i];
            unchecked {
                ++i;
            }
        }
    }

    function getGroups(uint16[] calldata indices) external view returns (Group[] memory g) {
        g = new Group[](indices.length);

        for (uint256 i; i < indices.length;) {
            g[i] = groups[indices[i]];
            unchecked {
                ++i;
            }
        }
    }

    function getTradeInitialAccFees(uint256 tradeIndex)
        external
        view
        returns (InitialAccFees memory feesAccrued, IFeesMarkets.TradeInitialAccFees memory otherFees)
    {
        uint256 id = initialAccFeeIds[tradeIndex];
        if (id < initialAccFees.length) feesAccrued = initialAccFees[id];
        otherFees = feesMarkets.tradeInitialAccFees(tradeIndex);
    }

    function getInitialAccFees(
        uint256 offset,
        uint256 count
    )
        external
        view
        override
        returns (InitialAccFees[] memory fees)
    {
        // If the count requested is 0 or the offset is beyond the array length, return an empty array.
        if (count == 0 || offset >= initialAccFees.length) return new InitialAccFees[](0);

        // Calculate the size of the array to return: smaller of `count` or `initialAccFees.length - offset`.
        uint256 outputSize = (offset + count > initialAccFees.length) ? initialAccFees.length - offset : count;

        // Initialize the array of results and populate.
        fees = new InitialAccFees[](outputSize);
        unchecked {
            for (uint256 i = 0; i < outputSize; ++i) {
                fees[i] = initialAccFees[offset + i];
            }
        }
    }
}
