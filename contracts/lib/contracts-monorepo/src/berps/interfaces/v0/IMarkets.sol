// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IMarkets {
    enum FeedCalculation {
        SINGULAR, // uses only the base price
        TRIANGULAR // uses the base / quote price

    }

    struct Feed {
        // Pyth Price Feed IDs for the base (and quote if necessary) currency AND HONEY-USD price feed ID.
        // The 0 index must be the HONEY-USD price feed ID.
        // The 1 index is the base price, the 2 index (if triangular) is the quote price.
        bytes32[] ids;
        // Whether the price requires a singular or triangular calculation.
        FeedCalculation feedCalculation;
        // If true, will use the confidence range of a price result. This implies the settlement of orders and
        // positions will occur at the boundaries of the price range rather than the usually used mean. This mechanism
        // serves to limit the uncertainty of price results and protect the protocol from unusual market conditions.
        //
        // The direction of the bound will depend on the buy/sell direction of the trade and favors the protocol over
        // the trader. For example, if a user opens a long trade and the price range is [14, 16], the trade will open
        // at 16. When the user tries to close this long position and the price range is now [20, 22], the trade will
        // close at 20.
        //
        // More info: https://docs.pyth.network/price-feeds/best-practices#confidence-intervals
        bool useConfSpread;
        // Will revert a trading operation if a price's confidence interval is wider than this value, i.e if the
        // σ/µ percentage (conf/price) of a given Pyth price result is greater than this value. Denominated in
        // PRECISION of 1e10, i.e. a desired confidence threshold of 5% should be set as 5e10.
        //
        // More info: https://docs.pyth.network/price-feeds/best-practices#confidence-intervals
        uint64 confThresholdP;
        // If true, will use EMA prices & confidence intervals over regular aggregated prices & confidence
        // intervals.
        //
        // More info: https://docs.pyth.network/price-feeds/how-pyth-works/ema-price-aggregation
        bool useEma;
    }

    struct Pair {
        string from; // name of the base currency
        string to; // name of the quote currency
        Feed feed;
        uint256 groupIndex;
        uint256 feeIndex;
    }

    struct Group {
        string name;
        uint256 minLeverage;
        uint256 maxLeverage;
        uint256 maxCollateralP; // % (of HONEY vault current balance)
    }

    struct Fee {
        string name;
        uint256 openFeeP; // PRECISION (% of leveraged pos)
        uint256 closeFeeP; // PRECISION (% of leveraged pos)
        uint256 limitOrderFeeP; // PRECISION (% of leveraged pos)
        uint256 minLevPosHoney; // 1e18 (collateral x leverage, useful for min fee)
    }

    // Events
    event PairAdded(uint256 index, string from, string to);
    event PairUpdated(uint256 index);
    event GroupAdded(uint256 index, string name);
    event GroupUpdated(uint256 index);
    event FeeAdded(uint256 index, string name);
    event FeeUpdated(uint256 index);

    /// @notice Only callable via a ERC1967 Proxy contract.
    function initialize(address _orders) external;

    function MAX_LEVERAGE() external view returns (uint256);

    function updateGroupCollateral(uint256, uint256, bool, bool) external;

    function isPairIndexListed(uint256) external view returns (bool);

    function pairFeed(uint256) external view returns (Feed memory);

    function pairMinLeverage(uint256) external view returns (uint256);

    function pairMaxLeverage(uint256) external view returns (uint256);

    function groupMaxCollateral(uint256) external view returns (uint256);

    function groupCollateral(uint256, bool) external view returns (uint256);

    function guaranteedSlEnabled(uint256) external view returns (bool);

    function pairOpenFeeP(uint256) external view returns (uint256);

    function pairCloseFeeP(uint256) external view returns (uint256);

    function pairLimitOrderFeeP(uint256) external view returns (uint256);

    function pairMinLevPosHoney(uint256) external view returns (uint256);

    function pairsCount() external view returns (uint256);
}
