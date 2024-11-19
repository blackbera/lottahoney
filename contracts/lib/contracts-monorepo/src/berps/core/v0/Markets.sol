// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IMarkets } from "../../interfaces/v0/IMarkets.sol";

import { IOrders, StorageUtils } from "./Orders.sol";

import { Utils } from "../../../libraries/Utils.sol";
import { BerpsErrors } from "../../utils/BerpsErrors.sol";
import { PythFeeds } from "../../utils/PythFeeds.sol";

contract Markets is UUPSUpgradeable, IMarkets {
    using StorageUtils for mapping(bytes32 => bool);
    using Utils for bytes4;

    // Contracts (constant)
    IOrders public orders;

    // Params (constant)
    uint256 constant MIN_LEVERAGE = 2;
    uint256 public constant MAX_LEVERAGE = 1000;

    // State
    uint256 public pairsCount;
    uint256 public groupsCount;
    uint256 public feesCount;

    mapping(uint256 => Pair) private pairs;
    mapping(uint256 => Group) private groups;
    mapping(uint256 => Fee) private fees;

    mapping(bytes32 => bool) public isPairListed;

    mapping(uint256 => uint256[2]) public groupsCollaterals; // (long, short)

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGov { }

    /// @inheritdoc IMarkets
    function initialize(address _orders) external initializer {
        if (_orders == address(0)) BerpsErrors.WrongParams.selector.revertWith();

        orders = IOrders(_orders);
    }

    // Modifiers
    modifier onlyGov() {
        if (msg.sender != orders.gov()) BerpsErrors.Unauthorized.selector.revertWith();
        _;
    }

    modifier pairListed(uint256 _pairIndex) {
        if (!isPairIndexListed(_pairIndex)) BerpsErrors.PairNotListed.selector.revertWith();
        _;
    }

    modifier groupListed(uint256 _groupIndex) {
        require(groups[_groupIndex].minLeverage > 0, "GROUP_NOT_LISTED");
        _;
    }

    modifier feeListed(uint256 _feeIndex) {
        require(fees[_feeIndex].openFeeP > 0, "FEE_NOT_LISTED");
        _;
    }

    /// @dev Ensure the feed is correctly configured. HONEY-USD must be the first price feed in the array.
    modifier feedOk(Feed calldata _feed) {
        require(_feed.ids[0] == PythFeeds.HONEY_USD, "WRONG_FEED");
        if (_feed.feedCalculation == FeedCalculation.SINGULAR) {
            require(_feed.ids.length == 2, "WRONG_FEED");
            require(_feed.ids[1] != bytes32(0), "WRONG_FEED");
        }
        if (_feed.feedCalculation == FeedCalculation.TRIANGULAR) {
            require(_feed.ids.length == 3, "WRONG_FEED");
            require(_feed.ids[1] != bytes32(0) && _feed.ids[2] != bytes32(0), "WRONG_FEED");
        }
        _;
    }

    modifier groupOk(Group calldata _group) {
        require(
            _group.minLeverage >= MIN_LEVERAGE && _group.maxLeverage <= MAX_LEVERAGE
                && _group.minLeverage < _group.maxLeverage,
            "WRONG_LEVERAGES"
        );
        _;
    }

    modifier feeOk(Fee calldata _fee) {
        require(
            _fee.openFeeP > 0 && _fee.closeFeeP > 0 /* && _fee.oracleFeeP > 0 */ && _fee.limitOrderFeeP > 0 /* &&
                _fee.referralFeeP > 0 */ && _fee.minLevPosHoney > 0,
            "WRONG_FEES"
        );
        _;
    }

    // Manage pairs
    function addPair(Pair calldata _pair)
        public
        onlyGov
        feedOk(_pair.feed)
        groupListed(_pair.groupIndex)
        feeListed(_pair.feeIndex)
    {
        require(!isPairListed.get(_pair.from, _pair.to), "PAIR_ALREADY_LISTED");

        pairs[pairsCount] = _pair;
        isPairListed.set(_pair.from, _pair.to);

        emit PairAdded(pairsCount++, _pair.from, _pair.to);
    }

    function addPairs(Pair[] calldata _pairs) external onlyGov {
        for (uint256 i = 0; i < _pairs.length; i++) {
            addPair(_pairs[i]);
        }
    }

    function updatePair(
        uint256 _pairIndex,
        Pair calldata _pair
    )
        external
        onlyGov
        pairListed(_pairIndex)
        feedOk(_pair.feed)
        feeListed(_pair.feeIndex)
    {
        Pair storage p = pairs[_pairIndex];
        p.feed = _pair.feed;
        p.feeIndex = _pair.feeIndex;
        emit PairUpdated(_pairIndex);
    }

    // Manage groups
    function addGroup(Group calldata _group) external onlyGov groupOk(_group) {
        groups[groupsCount] = _group;
        emit GroupAdded(groupsCount++, _group.name);
    }

    function updateGroup(uint256 _id, Group calldata _group) external onlyGov groupListed(_id) groupOk(_group) {
        groups[_id] = _group;
        emit GroupUpdated(_id);
    }

    // Manage fees
    function addFee(Fee calldata _fee) external onlyGov feeOk(_fee) {
        fees[feesCount] = _fee;
        emit FeeAdded(feesCount++, _fee.name);
    }

    function updateFee(uint256 _id, Fee calldata _fee) external onlyGov feeListed(_id) feeOk(_fee) {
        fees[_id] = _fee;
        emit FeeUpdated(_id);
    }

    // Update collateral open exposure for a group (settlement)
    function updateGroupCollateral(uint256 _pairIndex, uint256 _amount, bool _long, bool _increase) external {
        require(msg.sender == orders.settlement(), "CALLBACKS_ONLY");

        uint256[2] storage collateralOpen = groupsCollaterals[pairs[_pairIndex].groupIndex];
        uint256 index = _long ? 0 : 1;

        if (_increase) {
            collateralOpen[index] += _amount;
        } else {
            collateralOpen[index] = collateralOpen[index] > _amount ? collateralOpen[index] - _amount : 0;
        }
    }

    function isPairIndexListed(uint256 _pairIndex) public view returns (bool) {
        Pair memory p = pairs[_pairIndex];
        return isPairListed.get(p.from, p.to);
    }

    // Getters (pairs & groups)
    function pairFeed(uint256 _pairIndex) external view pairListed(_pairIndex) returns (Feed memory) {
        return pairs[_pairIndex].feed;
    }

    function pairMinLeverage(uint256 _pairIndex) external view pairListed(_pairIndex) returns (uint256) {
        return groups[pairs[_pairIndex].groupIndex].minLeverage;
    }

    function pairMaxLeverage(uint256 _pairIndex) external view pairListed(_pairIndex) returns (uint256) {
        return groups[pairs[_pairIndex].groupIndex].maxLeverage;
    }

    function groupMaxCollateral(uint256 _pairIndex) external view pairListed(_pairIndex) returns (uint256) {
        return (groups[pairs[_pairIndex].groupIndex].maxCollateralP * orders.vault().availableAssets()) / 100;
    }

    function groupCollateral(uint256 _pairIndex, bool _long) external view pairListed(_pairIndex) returns (uint256) {
        return groupsCollaterals[pairs[_pairIndex].groupIndex][_long ? 0 : 1];
    }

    function guaranteedSlEnabled(uint256 _pairIndex) external view pairListed(_pairIndex) returns (bool) {
        return pairs[_pairIndex].groupIndex == 0; // crypto only
    }

    // Getters (fees)
    function pairOpenFeeP(uint256 _pairIndex) external view pairListed(_pairIndex) returns (uint256) {
        return fees[pairs[_pairIndex].feeIndex].openFeeP;
    }

    function pairCloseFeeP(uint256 _pairIndex) external view pairListed(_pairIndex) returns (uint256) {
        return fees[pairs[_pairIndex].feeIndex].closeFeeP;
    }

    function pairLimitOrderFeeP(uint256 _pairIndex) external view pairListed(_pairIndex) returns (uint256) {
        return fees[pairs[_pairIndex].feeIndex].limitOrderFeeP;
    }

    function pairMinLevPosHoney(uint256 _pairIndex) external view pairListed(_pairIndex) returns (uint256) {
        return fees[pairs[_pairIndex].feeIndex].minLevPosHoney;
    }

    // Useful getters
    function getPair(uint256 _pairIndex)
        external
        view
        pairListed(_pairIndex)
        returns (Pair memory, Group memory, Fee memory)
    {
        Pair memory p = pairs[_pairIndex];
        return (p, groups[p.groupIndex], fees[p.feeIndex]);
    }

    function getAllPairs() external view returns (Pair[] memory, Group[] memory, Fee[] memory) {
        Pair[] memory p = new Pair[](pairsCount);
        Group[] memory g = new Group[](pairsCount);
        Fee[] memory f = new Fee[](pairsCount);

        for (uint256 i = 0; i < pairsCount;) {
            Pair memory pair = pairs[i];
            p[i] = pair;
            g[i] = groups[pair.groupIndex];
            f[i] = fees[pair.feeIndex];
            unchecked {
                ++i;
            }
        }

        return (p, g, f);
    }
}
