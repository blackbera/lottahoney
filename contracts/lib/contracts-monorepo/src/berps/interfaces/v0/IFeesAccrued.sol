// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IOrders } from "./IOrders.sol";
import { IFeesMarkets } from "./IFeesMarkets.sol";

interface IFeesAccrued {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct PairGroup {
        uint16 groupIndex;
        uint48 timestamp;
        uint64 initialAccFeeLong; // 1e10 (%)
        uint64 initialAccFeeShort; // 1e10 (%)
        uint64 prevGroupAccFeeLong; // 1e10 (%)
        uint64 prevGroupAccFeeShort; // 1e10 (%)
        uint64 pairAccFeeLong; // 1e10 (%)
        uint64 pairAccFeeShort; // 1e10 (%)
        uint64 _placeholder; // might be useful later
    }

    struct Pair {
        PairGroup[] groups;
        uint32 feePerSecond; // 1e10 (%)
        uint64 accFeeLong; // 1e10 (%)
        uint64 accFeeShort; // 1e10 (%)
        uint48 accLastUpdatedTime;
        uint48 _placeholder; // might be useful later
        uint256 lastAccTimeWeightedMarketCap; // 1e40
    }

    struct Group {
        uint112 oiLong; // 1e10
        uint112 oiShort; // 1e10
        uint32 feePerSecond; // 1e10 (%)
        uint64 accFeeLong; // 1e10 (%)
        uint64 accFeeShort; // 1e10 (%)
        uint48 accLastUpdatedTime;
        uint80 maxOi; // 1e10
        uint256 lastAccTimeWeightedMarketCap; // 1e40
    }

    struct InitialAccFees {
        uint256 tradeIndex;
        uint64 accPairFee; // 1e10 (%)
        uint64 accGroupFee; // 1e10 (%)
        uint48 timestamp;
        uint80 _placeholder; // might be useful later
    }

    struct PairParams {
        uint16 groupIndex;
        uint256 baseBorrowAPR; // 1e10 (%)
    }

    struct GroupParams {
        uint256 baseBorrowAPR; // 1e10 (%)
        uint80 maxOi; // 1e10
    }

    struct BorrowingFeeInput {
        uint256 pairIndex;
        uint256 tradeIndex;
        bool long;
        uint256 collateral; // 1e18 (HONEY)
        uint256 leverage;
    }

    struct LiqPriceInput {
        uint256 pairIndex;
        uint256 tradeIndex;
        int64 openPrice; // 1e10
        bool long;
        uint256 collateral; // 1e18 (HONEY)
        uint256 leverage;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event PairParamsUpdated(uint256 indexed pairIndex, uint16 indexed groupIndex, uint32 feePerSecond);
    event PairGroupUpdated(uint256 indexed pairIndex, uint16 indexed prevGroupIndex, uint16 indexed newGroupIndex);
    event GroupUpdated(uint16 indexed groupIndex, uint32 feePerSecond, uint80 maxOi);

    /// @notice Emitted when a trader opens a market position
    event TradeInitialAccFeesStored(uint256 tradeIndex, uint64 initialPairAccFee, uint64 initialGroupAccFees);

    event PairAccFeesUpdated(
        uint256 indexed pairIndex,
        uint256 currentTime,
        uint64 accFeeLong,
        uint64 accFeeShort,
        uint256 accBlockWeightedMarketCap
    );
    event GroupAccFeesUpdated(
        uint16 indexed groupIndex,
        uint256 currentTime,
        uint64 accFeeLong,
        uint64 accFeeShort,
        uint256 accBlockWeightedMarketCap
    );
    event GroupOiUpdated(
        uint16 indexed groupIndex,
        bool indexed long,
        bool indexed increase,
        uint112 amount,
        uint112 oiLong,
        uint112 oiShort
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Only callable via a ERC1967 Proxy contract.
    function initialize(address _orders, address _feesMarkets) external;

    /// @param input the necessary data to calculate liq price & borrow fee
    /// @return liqPrice the calculated liquidation price (in PRECISION of 1e10)
    /// @return borrowFee the HONEY amount of borrow fee for this trade (in precision of 1e18)
    function getTradeLiquidationPrice(LiqPriceInput calldata input)
        external
        view
        returns (int64 liqPrice, uint256 borrowFee);

    /// @param tradeIndices the indexes of the trades to calculate liquidation prices & borrow fees for
    /// @return liqPrices the calculated liquidation prices for each trade (in PRECISION of 1e10)
    /// @return borrowFees the HONEY amounts of borrow fees for each trade (in precision of 1e18)
    function getTradesLiquidationPrices(uint256[] calldata tradeIndices)
        external
        view
        returns (int64[] memory liqPrices, uint256[] memory borrowFees);

    function getTradeBorrowingFee(BorrowingFeeInput memory) external view returns (uint256); // 1e18 (HONEY)

    function handleTradeAction(
        uint256 pairIndex,
        uint256 index,
        uint256 positionSizeHoney, // 1e18 (collateral * leverage)
        bool open,
        bool long
    )
        external;

    function withinMaxGroupOi(uint256 pairIndex, bool long, uint256 positionSizeHoney) external view returns (bool);

    /// @notice used to get the current borrowing APR estimate for the given pair indices
    function getPairsCurrentAPR(uint256[] calldata indices)
        external
        view
        returns (uint256[] memory borrowAPRLong, uint256[] memory borrowAPRShort);

    /// @notice used to get the current borrowing APR estimate for the given group indices
    function getGroupsCurrentAPR(uint16[] calldata indices)
        external
        view
        returns (uint256[] memory borrowAPRLong, uint256[] memory borrowAPRShort);

    function getInitialAccFees(uint256 offset, uint256 count) external view returns (InitialAccFees[] memory);
}
