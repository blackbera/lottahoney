// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "solady/src/utils/SafeCastLib.sol";

import { IPyth } from "@pythnetwork/IPyth.sol";
import { PythStructs } from "@pythnetwork/PythStructs.sol";

import { BerpsErrors } from "./BerpsErrors.sol";

import { IEntrypoint } from "../interfaces/v0/IEntrypoint.sol";
import { IMarkets } from "../interfaces/v0/IMarkets.sol";

library PriceUtils {
    using FixedPointMathLib for uint256;
    using SafeCastLib for int256;

    uint256 constant DECIMALS = 10; // 10 DECIMALS in PRECISION
    int256 constant PRECISION = 1e10; // Berps uses a price PRECISION of 1e10
    uint256 constant PRECISION_2 = 1e20; // PRECISION^2 for calculations
    uint256 constant MAX_PERCENT = 1e12; // 100% in PRECISION

    int64 constant MAX_SL_P = -75e10; // PRECISION (-75% PnL)
    int64 constant MAX_GAIN_P = 900e10; // PRECISION (900% PnL, 10x)

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            PYTH                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice scales a given Pyth Price to the used price PRECISION of 1e10
    /// @param pythPrice the Pyth Price to scale
    /// @dev this function reverts if pythPrice.expo is positive
    /// @dev this function reverts if the returned price from Pyth is <= 0
    /// @return scaledPrice the scaled price as a int256
    /// @return scaledConf the scaled confidence interval as a uint256
    function scalePythPrice(PythStructs.Price memory pythPrice) internal pure returns (int256, uint256) {
        if (pythPrice.price <= 0) revert BerpsErrors.MarketClosed();
        if (pythPrice.expo > 0) revert BerpsErrors.InvalidExpo(pythPrice.expo);

        uint256 pythDecimals = uint32(-pythPrice.expo);
        if (pythDecimals < DECIMALS) {
            uint256 scaleUp = 10 ** (DECIMALS - pythDecimals);
            return (pythPrice.price * int256(scaleUp), pythPrice.conf * scaleUp);
        } else if (pythDecimals > DECIMALS) {
            uint256 scaleDown = 10 ** (pythDecimals - DECIMALS);
            return (pythPrice.price / int256(scaleDown), pythPrice.conf / scaleDown);
        } else {
            return (pythPrice.price, pythPrice.conf);
        }
    }

    /// @notice returns the spread price based on the mean and confidence interval. It returns the boundary of the
    /// confidence interval that favors the protocol over the trader. For more info, refer to IMarkets.Feed
    /// @param mean the mean price (PRECISION of 1e10)
    /// @param spread the confidence interval spread (PRECISION of 1e10)
    /// @param buy the direction of the trade (true for long, false for short)
    /// @param isOpen true if a position is being opened, false if a position is being closed
    /// @return spreadPrice the price to be used for the trade (PRECISION of 1e10) as a int256
    function getSpreadPrice(int256 mean, uint256 spread, bool buy, bool isOpen) internal pure returns (int256) {
        return (buy != isOpen) ? mean - int256(spread) : mean + int256(spread);
    }

    /// @notice gets the price and confidence interval for a triangular calculation
    /// @param p base price, required to be nonzero (PRECISION of 1e10)
    /// @param a base confidence interval (PRECISION of 1e10)
    /// @param q quote price, required to be nonzero (PRECISION of 1e10)
    /// @param b quote confidence interval (PRECISION of 1e10)
    /// @dev logic from Pyth Rust SDK https://github.com/pyth-network/pyth-sdk-rs/blob/main/pyth-sdk/src/price.rs#L424
    /// @dev price: r = p/q, conf: c = p/q * sqrt((a/p)^2 + (b/q)^2)
    /// @return r triangular price, which divides the base price by the quote price (PRECISION of 1e10), as a int256
    /// @return c triangular confidence interval (PRECISION of 1e10), as a uint256
    function getTriangularResult(uint256 p, uint256 a, uint256 q, uint256 b) internal pure returns (int256, uint256) {
        uint256 r = p.fullMulDiv(uint256(PRECISION), q);
        uint256 c = r.fullMulDivUp(
            ((a * a).fullMulDiv(PRECISION_2, p * p) + (b * b).fullMulDiv(PRECISION_2, q * q)).sqrt(),
            uint256(PRECISION)
        );
        return (int256(r), c);
    }

    /// @notice gets the price from Pyth for the given pair feed, determines validity, and scales to PRECISION of 1e10
    /// @notice returns the execution price with the "fixed spread" (from the Pyth confidence interval) applied
    /// @param pyth the Pyth contract
    /// @dev this function reverts with BerpsErrors.InvalidExpo if Pyth returns with a positive exponent
    /// @dev this function reverts with BerpsErrors.MarketClosed if the returned price from Pyth is <= 0
    /// @param feed the pair feed to get the price for
    /// @dev this function reverts with BerpsErrors.InvalidConfidence if the returned confidence interval from Pyth
    /// is greater than the configured threshold for the feed.
    /// @dev the price depends on the feed calculation. If singular, the resulting price is the base price. If the
    /// triangular, the resulting price is the base price divided by the quote price.
    /// @param buy the direction of the trade (true for long, false for short)
    /// @param isOpen true if a position is being opened, false if a position is being closed
    /// @return price the executable price (PRECISION of 1e10) as an int64
    function getPythExecutionPrice(
        IPyth pyth,
        IMarkets.Feed memory feed,
        bool buy,
        bool isOpen
    )
        internal
        view
        returns (int64)
    {
        // Get the base currency price and confidence interval.
        (int256 basePrice, uint256 baseConf) = getValidPythPrice(pyth, feed, 1);

        // If the feed calculation is singular, return the base and HONEY prices.
        if (feed.feedCalculation == IMarkets.FeedCalculation.SINGULAR) {
            if (feed.useConfSpread) {
                return getSpreadPrice(basePrice, baseConf, buy, isOpen).toInt64();
            } else {
                return basePrice.toInt64();
            }
        }

        // Get the quote currency price and confidence interval.
        (int256 quotePrice, uint256 quoteConf) = getValidPythPrice(pyth, feed, 2);

        // Calculate and return the triangular price and confidence interval for base and HONEY prices.
        (int256 triangularPrice, uint256 triangularConf) =
            getTriangularResult(uint256(basePrice), baseConf, uint256(quotePrice), quoteConf);
        if (feed.useConfSpread) {
            return getSpreadPrice(triangularPrice, triangularConf, buy, isOpen).toInt64();
        } else {
            return triangularPrice.toInt64();
        }
    }

    /// @notice gets the price for HONEY in terms of the desired quote currency (PRECISION of 1e10)
    /// @param pyth the Pyth contract
    /// @dev this function reverts with BerpsErrors.InvalidExpo if Pyth returns with a positive exponent
    /// @dev this function reverts with BerpsErrors.MarketClosed if the returned price from Pyth is <= 0
    /// @param feed the pair feed to get the price
    /// @dev this function reverts with BerpsErrors.InvalidConfidence if the returned confidence interval from Pyth
    /// is greater than the configured threshold for the feed.
    /// @dev the price depends on the feed calculation. If singular, the resulting price is the base price. If the
    /// triangular, the resulting price is the base price divided by the quote price.
    /// @return priceHoney the executable price for HONEY in terms of the desired quote currency (PRECISION of 1e10)
    /// as an int64. If singular, returns the raw HONEY-USD price. If triangular, returns the HONEY-USD price divided
    /// by the quote price.
    function getPythExecutionPriceHoney(IPyth pyth, IMarkets.Feed memory feed) internal view returns (int64) {
        // Get the HONEY price and confidence interval.
        (int256 priceHoney, uint256 confHoney) = getValidPythPrice(pyth, feed, 0);
        if (feed.feedCalculation == IMarkets.FeedCalculation.SINGULAR) {
            return priceHoney.toInt64();
        }

        // Get the quote currency price and confidence interval.
        (int256 quotePrice, uint256 quoteConf) = getValidPythPrice(pyth, feed, 2);

        // Calculate and return the triangular price.
        (int256 triangularPriceHoney,) =
            getTriangularResult(uint256(priceHoney), confHoney, uint256(quotePrice), quoteConf);
        return triangularPriceHoney.toInt64();
    }

    /// @notice gets the price from Pyth and scales it to PRECISION of 1e10 for the given feed id
    /// @param pyth the Pyth contract
    /// @dev this function reverts with BerpsErrors.InvalidExpo if Pyth returns with a positive exponent
    /// @dev this function reverts with BerpsErrors.MarketClosed if the returned price from Pyth is <= 0
    /// @param feed the pair feed to get the price for
    /// @param idx the idx of the feed ids to get the price for
    /// @dev this function reverts with BerpsErrors.InvalidConfidence if the returned confidence interval from Pyth
    /// is greater than the configured threshold for the feed
    /// @return price the price (PRECISION of 1e10) as an int256
    /// @return conf the confidence interval (PRECISION of 1e10) as an uint256
    function getValidPythPrice(
        IPyth pyth,
        IMarkets.Feed memory feed,
        uint256 idx
    )
        internal
        view
        returns (int256, uint256)
    {
        PythStructs.Price memory pythPrice =
            feed.useEma ? pyth.getEmaPrice(feed.ids[idx]) : pyth.getPrice(feed.ids[idx]);
        (int256 price, uint256 conf) = scalePythPrice(pythPrice);
        if (conf.fullMulDivUp(MAX_PERCENT, uint256(price)) > feed.confThresholdP) {
            revert BerpsErrors.InvalidConfidence(conf.fullMulDivUp(MAX_PERCENT, uint256(price)));
        }
        return (price, conf);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           TRADING                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice calculates the current percent of profit of loss of a trade
    /// @param currentPrice the current price to base the calculation off of (PRECISION of 1e10)
    /// @param openPrice open price of the trade (PRECISION of 1e10)
    /// @dev this function reverts if any price is <= 0
    /// @param buy whether the trade is long or short -- true for long, false for short
    /// @param leverage the leverage of the trade
    /// @return percentProfit % profit in PRECISION of 1e10 as a int64
    function currentPercentProfit(
        int64 currentPrice,
        int64 openPrice,
        bool buy,
        uint256 leverage
    )
        internal
        pure
        returns (int64 percentProfit)
    {
        if (currentPrice <= 0 || openPrice <= 0) revert BerpsErrors.MarketClosed();

        // use int256 here to avoid overflow during multiplication
        int256 rawP = (buy ? currentPrice - openPrice : openPrice - currentPrice) * int256(MAX_PERCENT)
            * int256(leverage) / openPrice;

        // TODO: if this overflows, propogate a better error? or revert with MarketClosed()?
        percentProfit = rawP.toInt64();
        if (percentProfit > MAX_GAIN_P) percentProfit = MAX_GAIN_P;
    }

    /// @notice calculates the correct TP for a trade, given the max gain of 900%
    /// @param tp the given TP to caluclate on -- if valid or unset as is, it's returned unchanged
    /// @param openPrice open price of the trade (PRECISION of 1e10)
    /// @dev this function reverts if openPrice <= 0
    /// @param buy whether the trade is long or short -- true for long, false for short
    /// @param leverage the leverage of the trade
    /// @return correctTP the corrected TP (PRECISION of 1e10) as a int64
    function correctTp(int64 tp, int64 openPrice, bool buy, uint256 leverage) internal pure returns (int64) {
        if (openPrice <= 0) revert BerpsErrors.MarketClosed();

        if (tp == 0 || currentPercentProfit(tp, openPrice, buy, leverage) == MAX_GAIN_P) {
            int64 tpDiff = maxTpDist(openPrice, leverage);

            tp = buy ? openPrice + tpDiff : (tpDiff < openPrice ? openPrice - tpDiff : int64(0));
        }

        return tp;
    }

    /// @notice calculates the maximum distance from the open price for the TP, given the max gain of 900%
    /// @param openPrice open price of the trade (PRECISION of 1e10)
    /// @param leverage the leverage of the trade
    /// @return tpDiff the maximum distance from the open price for the TP (PRECISION of 1e10) as a int64
    function maxTpDist(int64 openPrice, uint256 leverage) internal pure returns (int64) {
        // use int256 here to avoid overflow during multiplication
        int256 rawDiff = (int256(openPrice) * int256(MAX_GAIN_P)) / int256(leverage) / int256(MAX_PERCENT);

        // TODO: if this overflows, propogate a better error? or revert with MarketClosed()?
        return rawDiff.toInt64();
    }

    /// @notice calculates the correct SL for a trade, given the max SL of -75%
    /// @param sl the given SL to caluclate on -- if valid or unset as is, it's returned unchanged
    /// @param openPrice open price of the trade (PRECISION of 1e10)
    /// @dev this function reverts if openPrice is <= 0
    /// @param buy whether the trade is long or short -- true for long, false for short
    /// @param leverage the leverage of the trade
    /// @return correctSL the corrected SL (PRECISION of 1e10) as a int64
    function correctSl(int64 sl, int64 openPrice, bool buy, uint256 leverage) internal pure returns (int64) {
        if (openPrice <= 0) revert BerpsErrors.MarketClosed();

        if (sl > 0 && currentPercentProfit(sl, openPrice, buy, leverage) < MAX_SL_P) {
            int64 slDiff = maxSlDist(openPrice, leverage);

            sl = buy ? (slDiff < openPrice ? openPrice - slDiff : int64(0)) : openPrice + slDiff;
        }

        return sl;
    }

    /// @notice calculates the maximum abs distance from the open price for the SL, given the max SL of -75%
    /// @param openPrice open price of the trade (PRECISION of 1e10)
    /// @param leverage the leverage of the trade
    /// @return slDiff the maximum absolute distance from the open price for the SL (PRECISION of 1e10) as a int64
    /// @dev slDiff is returned as an absolute value. For a long position, slDiff should be subtracted from open price.
    /// For a short position, slDiff should be added to the open price.
    function maxSlDist(int64 openPrice, uint256 leverage) internal pure returns (int64) {
        // use int256 here to avoid overflow during multiplication
        int256 rawDiff = (int256(openPrice) * int256(-MAX_SL_P)) / int256(leverage) / int256(MAX_PERCENT);

        // TODO: if this overflows, propogate a better error? or revert with MarketClosed()?
        return rawDiff.toInt64();
    }
}
