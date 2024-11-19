// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IFeesMarkets {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct TradeInitialAccFees {
        uint256 tradeIndex;
        uint256 rollover; // 1e18 (HONEY)
        int256 funding; // 1e18 (HONEY)
        bool openedAfterUpdate;
    }

    struct PairParams {
        uint256 onePercentDepthAbove; // HONEY
        uint256 onePercentDepthBelow; // HONEY
        uint256 rolloverFeePerBlockP; // PRECISION (%) // rolling over when position open (flat fee)
        uint256 fundingFeePerBlockP; // PRECISION (%) // funding fee per block (received/provided for long/short)
    }

    struct PairFundingFees {
        int256 accPerOiLong; // 1e18 (HONEY) // accrued funding fee per oi long
        int256 accPerOiShort; // 1e18 (HONEY) // accrued funding fee per oi short
        uint256 lastUpdateBlock;
    }

    // accrued per collateral
    struct PairRolloverFees {
        uint256 accPerCollateral; // 1e18 (HONEY)
        uint256 lastUpdateBlock;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event ManagerUpdated(address value);
    event MaxNegativePnlOnOpenPUpdated(int64 value);
    event PairParamsUpdated(uint256 indexed pairIndex, PairParams value);
    event OnePercentDepthUpdated(uint256 indexed pairIndex, uint256 valueAbove, uint256 valueBelow);
    event RolloverFeePerBlockPUpdated(uint256 indexed pairIndex, uint256 value);
    event FundingFeePerBlockPUpdated(uint256 indexed pairIndex, uint256 value);

    /// @notice Emitted when a market position is opened
    event TradeInitialAccFeesStored(uint256 index, uint256 rollover, int256 funding);

    event AccFundingFeesStored(uint256 indexed pairIndex, int256 valueLong, int256 valueShort);
    event AccRolloverFeesStored(uint256 indexed pairIndex, uint256 value);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Only callable via a ERC1967 Proxy contract.
    function initialize(address _orders, address _manager, int64 _maxNegativePnlOnOpenP) external;

    function tradeInitialAccFees(uint256) external view returns (TradeInitialAccFees memory);

    function getTradeInitialAccFees(
        uint256 offset,
        uint256 count
    )
        external
        view
        returns (TradeInitialAccFees[] memory);

    function maxNegativePnlOnOpenP() external view returns (int64); // PRECISION (%)

    function storeTradeInitialAccFees(uint256 pairIndex, uint256 index, bool long) external;

    /// @notice Dynamic price impact value on trade opening.
    /// @param currentPrice The current price of the pair (from oracle) in PRECISION.
    /// @param pairIndex The index of the pair.
    /// @param long Whether the trade is long or short.
    /// @param tradeOpenInterest The new open interest of the trade caused by this trade in precision of 1e18 (HONEY).
    /// @return priceImpactP The price impact of the trade in PRECISION %.
    /// @return priceAfterImpact The price after the trade impact in PRECISION, should be used as trade's opening
    /// price.
    function getTradePriceImpact(
        int64 currentPrice,
        uint256 pairIndex,
        bool long,
        uint256 tradeOpenInterest
    )
        external
        view
        returns (int64 priceImpactP, int64 priceAfterImpact);

    function getTradeRolloverFee(
        uint256 pairIndex,
        uint256 index,
        uint256 collateral // 1e18 (HONEY)
    )
        external
        view
        returns (uint256);

    function getTradeFundingFee(
        uint256 pairIndex,
        uint256 index,
        bool long,
        uint256 collateral, // 1e18 (HONEY)
        uint256 leverage
    )
        external
        view
        returns (int256); // 1e18 (HONEY) | Positive => Fee,
        // Negative
        // => Reward

    function getTradeLiquidationPricePure(
        int64 openPrice, // PRECISION
        bool long,
        uint256 collateral, // 1e18 (HONEY)
        uint256 leverage,
        uint256 rolloverFee, // 1e18 (HONEY)
        int256 fundingFee // 1e18 (HONEY)
    )
        external
        pure
        returns (int64);

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
        returns (int64); // PRECISION

    function getTradeValue(
        uint256 pairIndex,
        uint256 index,
        bool long,
        uint256 collateral, // 1e18 (HONEY)
        uint256 leverage,
        int256 percentProfit, // PRECISION (%)
        uint256 closingFee // 1e18 (HONEY)
    )
        external
        returns (uint256 value, uint256 rolloverFee, int256 fundingFee); // 1e18 (HONEY)

    function manager() external view returns (address);
}
