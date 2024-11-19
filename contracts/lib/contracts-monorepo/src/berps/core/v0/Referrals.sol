// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Utils } from "../../../libraries/Utils.sol";
import { BerpsErrors } from "../../utils/BerpsErrors.sol";

import { IReferrals, IOrdersForReferrals } from "../../interfaces/v0/IReferrals.sol";

contract Referrals is UUPSUpgradeable, IReferrals {
    using Utils for bytes4;

    // CONSTANTS
    uint256 constant PRECISION = 1e10;
    uint256 constant MAX_PERCENT = 100; // 100%
    uint256 constant MAX_OPEN_FEE_P = 50; // 50% of the open fee used for referral rewards.

    IOrdersForReferrals public orders;

    // ADJUSTABLE PARAMETERS
    uint256 public startReferrerFeeP; // % (of referrer fee when 0 volume referred, eg. 75)
    uint256 public openFeeP; // % (of opening fee used for referral system, eg. 33)
    uint256 public targetVolumeHoney; // HONEY in 1e18 precision (to reach maximum referral system fee, eg. 1e24 is 1
        // million HONEY in volume)

    // STATE (MAPPINGS)
    mapping(address => uint256) private referrerDetailsIds;
    ReferrerDetails[] private _referrerDetails;
    mapping(address => address) private referrerByTrader;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyGov { }

    /// @inheritdoc IReferrals
    function initialize(
        address _orders,
        uint256 _startReferrerFeeP,
        uint256 _openFeeP,
        uint256 _targetVolumeHoney
    )
        external
        initializer
    {
        if (
            _orders == address(0) || _startReferrerFeeP > MAX_PERCENT || _openFeeP > MAX_OPEN_FEE_P
                || _targetVolumeHoney == 0
        ) BerpsErrors.WrongParams.selector.revertWith();

        orders = IOrdersForReferrals(_orders);
        startReferrerFeeP = _startReferrerFeeP;
        openFeeP = _openFeeP;
        targetVolumeHoney = _targetVolumeHoney;

        // Set the 0 index of the _referrerDetails array to be empty (unused).
        _referrerDetails.push(ReferrerDetails(new address[](0), 0, 0, 0, 0));
    }

    // MODIFIERS
    modifier onlyGov() {
        if (msg.sender != orders.gov()) BerpsErrors.Unauthorized.selector.revertWith();
        _;
    }

    modifier onlySettlement() {
        if (msg.sender != orders.settlement()) BerpsErrors.Unauthorized.selector.revertWith();
        _;
    }

    // MANAGE PARAMETERS
    function updateStartReferrerFeeP(uint256 value) external onlyGov {
        if (value > MAX_PERCENT) BerpsErrors.WrongParams.selector.revertWith();

        startReferrerFeeP = value;

        emit UpdatedStartReferrerFeeP(value);
    }

    function updateOpenFeeP(uint256 value) external onlyGov {
        if (value > MAX_OPEN_FEE_P) BerpsErrors.WrongParams.selector.revertWith();

        openFeeP = value;

        emit UpdatedOpenFeeP(value);
    }

    function updateTargetVolumeHoney(uint256 value) external onlyGov {
        if (value == 0) BerpsErrors.WrongParams.selector.revertWith();

        targetVolumeHoney = value;

        emit UpdatedTargetVolumeHoney(value);
    }

    // MANAGE REFERRERS
    function registerPotentialReferrer(address referrer) external {
        if (referrer == address(0) || referrer == msg.sender) BerpsErrors.InvalidReferrer.selector.revertWith();
        if (referrerByTrader[msg.sender] != address(0)) BerpsErrors.AlreadyReferred.selector.revertWith();

        uint256 senderId = referrerDetailsIds[msg.sender];
        if (senderId > 0) {
            address[] memory tradersRefs = _referrerDetails[senderId].tradersReferred;
            for (uint256 i; i < tradersRefs.length;) {
                if (tradersRefs[i] == referrer) BerpsErrors.ReferralCycle.selector.revertWith();
                unchecked {
                    ++i;
                }
            }
        }

        uint256 referrerId = referrerDetailsIds[referrer];
        if (referrerId == 0) {
            // If the referrer doesn't already exist, create a new ReferrerDetails.
            address[] memory tradersReferred = new address[](1);
            tradersReferred[0] = msg.sender;

            referrerDetailsIds[referrer] = _referrerDetails.length;
            _referrerDetails.push(ReferrerDetails(tradersReferred, 0, 0, 0, 0));
        } else {
            _referrerDetails[referrerId].tradersReferred.push(msg.sender);
        }
        referrerByTrader[msg.sender] = referrer;

        emit ReferrerRegistered(msg.sender, referrer);
    }

    // REWARDS DISTRIBUTION
    function distributePotentialReward(
        address trader,
        uint256 volumeHoney,
        uint256 pairOpenFeeP // PRECISION
    )
        external
        onlySettlement
        returns (uint256)
    {
        address referrer = referrerByTrader[trader];
        uint256 referrerId = referrerDetailsIds[referrer];
        if (referrerId == 0) return 0;
        ReferrerDetails storage r = _referrerDetails[referrerId];

        uint256 referrerRewardValueHoney =
            (volumeHoney * getReferrerFeeP(pairOpenFeeP, r.volumeReferredHoney)) / PRECISION / MAX_PERCENT;
        orders.transferHoney(address(orders), referrer, referrerRewardValueHoney);

        r.volumeReferredHoney += volumeHoney;
        r.totalRewardsValueHoney += referrerRewardValueHoney;

        emit ReferrerRewardDistributed(referrer, trader, volumeHoney, referrerRewardValueHoney);

        return referrerRewardValueHoney;
    }

    // VIEW FUNCTIONS
    function getReferrerFeeP(uint256 pairOpenFeeP, uint256 volumeReferredHoney) private view returns (uint256) {
        uint256 maxReferrerFeeP = (pairOpenFeeP * 2 * openFeeP) / MAX_PERCENT;
        uint256 minFeeP = (maxReferrerFeeP * startReferrerFeeP) / MAX_PERCENT;

        uint256 feeP = minFeeP + ((maxReferrerFeeP - minFeeP) * volumeReferredHoney) / targetVolumeHoney;

        return feeP > maxReferrerFeeP ? maxReferrerFeeP : feeP;
    }

    /// @return percentOfOpenFeeP percentage of open fee to distribute as referrer reward as a % (PRECISION of 1e10)
    function getPercentOfOpenFeeP(address trader) external view returns (uint256) {
        return getPercentOfOpenFeeP_calc(
            _referrerDetails[referrerDetailsIds[referrerByTrader[trader]]].volumeReferredHoney
        );
    }

    function getPercentOfOpenFeeP_calc(uint256 volumeReferredHoney) public view returns (uint256 resultP) {
        resultP = (
            openFeeP
                * (
                    startReferrerFeeP * PRECISION
                        + (volumeReferredHoney * PRECISION * (MAX_PERCENT - startReferrerFeeP)) / targetVolumeHoney
                )
        ) / MAX_PERCENT;

        resultP = resultP > openFeeP * PRECISION ? openFeeP * PRECISION : resultP;
    }

    function getTraderReferrer(address trader) external view returns (address) {
        return referrerByTrader[trader];
    }

    function referrersCount() external view returns (uint256) {
        return _referrerDetails.length - 1; // Exclude the 0 index of this array.
    }

    /// @notice returns empty ReferrerDetails struct if referrer doens't exist
    function getReferrerDetails(address referrer) external view returns (ReferrerDetails memory) {
        return _referrerDetails[referrerDetailsIds[referrer]];
    }

    function getAllReferrerDetails(
        uint256 offset,
        uint256 count
    )
        external
        view
        returns (ReferrerDetails[] memory details)
    {
        // If the count requested is 0 or the offset is beyond the array length, return an empty array.
        if (count == 0 || offset >= _referrerDetails.length) return new ReferrerDetails[](0);

        // Calculate the size of the array to return: smaller of `count` or `_referrerDetails.length - offset`.
        uint256 outputSize = (offset + count > _referrerDetails.length) ? _referrerDetails.length - offset : count;

        // Initialize the array of results and populate.
        details = new ReferrerDetails[](outputSize);
        unchecked {
            for (uint256 i = 0; i < outputSize; ++i) {
                details[i] = _referrerDetails[offset + i];
            }
        }
    }
}
