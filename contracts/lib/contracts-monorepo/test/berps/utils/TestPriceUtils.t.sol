// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import "src/berps/utils/PriceUtils.sol";

contract TestPriceUtils is Test {
    uint256 constant PRECISION = 1e10;

    function testSimpleTriangular() public pure {
        // p: 3, a, 1, q: 4, b: 1 --> r: 3/4, c: 5/16
        // a/p: 0.333 (33.3%), b/q: 0.25 (25%) --> c/r: 0.417 (41.7%)
        // makes sense that the conf % is amplified from 33% and 25% to 41.7%
        (int256 r, uint256 c) = PriceUtils.getTriangularResult(3 * PRECISION, PRECISION, 4 * PRECISION, PRECISION);
        assertEq(r, int256(3 * PRECISION / 4), "Price should be correctly calculated");
        assertEq(c, 5 * PRECISION / 16, "Confidence should be correctly calculated");
    }

    // expecting inputs' conf % <= 0.1%
    function testPythTriangular() public pure {
        // p: 1000, a: 1, q: 10000, b: 5 --> r: 1/10, c: ~0.000112
        // a/p: 0.001 (0.1%), b/q: 0.0005 (0.05%) --> c/r: ~0.00112 (0.112%)
        // makes sense that the conf % is amplified from 0.1% and 0.05% to 0.112%
        (int256 r, uint256 c) =
            PriceUtils.getTriangularResult(1000 * PRECISION, PRECISION, 10_000 * PRECISION, 5 * PRECISION);
        assertEq(r, int256(1 * PRECISION / 10), "Price should be correctly calculated");
        assertEq(c, 1_118_034, "Confidence should be correctly calculated");
    }

    function testCurrentPercentProfit() public pure {
        int64 currentPrice = 120e10; // 120 with 10 decimals
        int64 openPrice = 100e10; // 100 with 10 decimals
        bool buy = true;
        uint256 leverage = 10;

        int64 percentProfit = PriceUtils.currentPercentProfit(currentPrice, openPrice, buy, leverage);
        assertEq(percentProfit, 200e10); // Expecting 200% profit with 10 decimals

        currentPrice = 80e10; // 80 with 10 decimals
        buy = false;
        percentProfit = PriceUtils.currentPercentProfit(currentPrice, openPrice, buy, leverage);
        assertEq(percentProfit, 200e10); // Expecting 200% profit with 10 decimals
    }

    function testCurrentPercentProfitRevertsIfPriceZero() public {
        int64 currentPrice = 0;
        int64 openPrice = 100e10;
        bool buy = true;
        uint256 leverage = 10;

        vm.expectRevert(BerpsErrors.MarketClosed.selector);
        PriceUtils.currentPercentProfit(currentPrice, openPrice, buy, leverage);
    }

    function testCorrectTp() public pure {
        int64 openPrice = 100e10; // 100 with 10 decimals
        int64 tp = 150e10; // 150 with 10 decimals
        bool buy = true;
        uint256 leverage = 10;

        int64 correctTp = PriceUtils.correctTp(tp, openPrice, buy, leverage);
        assertEq(correctTp, 150e10); // Expecting the same TP as it's valid

        tp = 0; // Unset TP
        correctTp = PriceUtils.correctTp(tp, openPrice, buy, leverage);
        assertEq(correctTp, 190e10); // Expecting corrected TP to be 190 with 10 decimals

        tp = 200e10; // TP above max gain
        correctTp = PriceUtils.correctTp(tp, openPrice, buy, leverage);
        assertEq(correctTp, 190e10); // Should return max TP
    }

    function testMaxTpDist() public pure {
        int64 openPrice = 100e10; // 100 with 10 decimals
        uint256 leverage = 10;

        int64 tpDiff = PriceUtils.maxTpDist(openPrice, leverage);
        assertEq(tpDiff, 90e10); // Expecting TP distance to be 90 with 10 decimals
    }

    function testCorrectSl() public pure {
        int64 openPrice = 100e10; // 100 with 10 decimals
        int64 sl = 95e10; // 95 with 10 decimals
        bool buy = true;
        uint256 leverage = 10;

        int64 correctSl = PriceUtils.correctSl(sl, openPrice, buy, leverage);
        assertEq(correctSl, 95e10); // Expecting the same SL as it's valid

        sl = 0; // Unset SL
        correctSl = PriceUtils.correctSl(sl, openPrice, buy, leverage);
        assertEq(correctSl, 0); // Unset SL is returned

        sl = 90e10; // SL below max loss
        correctSl = PriceUtils.correctSl(sl, openPrice, buy, leverage);
        assertEq(correctSl, 92.5e10); // Should return max SL of 92.5

        buy = false;
        sl = 105e10; // 105 with 10 decimals

        correctSl = PriceUtils.correctSl(sl, openPrice, buy, leverage);
        assertEq(correctSl, 105e10); // Expecting the same SL as it's valid

        sl = 0; // Unset SL
        correctSl = PriceUtils.correctSl(sl, openPrice, buy, leverage);
        assertEq(correctSl, 0); // Unset SL is returned

        sl = 110e10; // SL below max loss
        correctSl = PriceUtils.correctSl(sl, openPrice, buy, leverage);
        assertEq(correctSl, 107.5e10); // Should return max SL of 107.5
    }

    function testMaxSlDist() public pure {
        int64 openPrice = 100e10; // 100 with 10 decimals
        uint256 leverage = 10;

        int64 slDiff = PriceUtils.maxSlDist(openPrice, leverage);
        assertEq(slDiff, 7.5e10); // Expecting SL distance to be 7.5 with 10 decimals
    }
}
