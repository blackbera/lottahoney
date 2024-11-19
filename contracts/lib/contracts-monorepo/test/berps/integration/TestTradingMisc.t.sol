// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { BerpsErrors } from "src/berps/utils/BerpsErrors.sol";

import { IOrders } from "src/berps/interfaces/v0/IOrders.sol";
import { ISettlement } from "src/berps/interfaces/v0/ISettlement.sol";

import { BaseTradingTest } from "./BaseTradingTest.t.sol";

contract TestTradingMisc is BaseTradingTest {
    address trader = address(0x1111);
    bytes[] priceUpdates;
    uint256 initialHoneyBalance = 50e18;

    function setUp() public override {
        super.setUp();
        initializeTrading(0); // Oracle update fee is 0 for these tests.

        honey.mint(trader, initialHoneyBalance);
        vm.prank(trader, trader);
        honey.approve(address(orders), type(uint256).max);
    }

    // Demonstrates passing in large `openPrice` and `sl` for trade type
    // REVERSAL (LIMIT) will
    // abuse `currentPercentProfit` to return `maxPnLP` => bot can close trade
    // with 900% profit.
    //
    // ✅ Resolved by disallowing REVERSAL in favor of solely using MOMENTUM
    // LIMIT orders.
    //
    // Logs:
    // honey balance: 50000000000000000000
    // honey balance: 40000000000000000000
    // honey balance: 40000000000000000000
    // honey balance: 133623999947296095000 (before) --> 48100000000000000000 (now)
    function testTradingSL() external {
        vm.startPrank(trader, trader);

        console.log("honey balance: %s", honey.balanceOf(trader));
        IOrders.Trade memory t = IOrders.Trade(
            trader,
            0,
            0,
            0,
            10_000_000_000_000_000_000,
            0x7FFFFFFFFFFFFFFE, // target: max(int64) - 1
            true,
            100,
            0x7FFFFFFFFFFFFFFF, // TP: max(int64)
            0x7FFFFFFFFFFFFFFD // SL: max(int64) - 2
        );

        uint64 publishTime = uint64(block.timestamp - 5 seconds);

        // Trader opens a limit order, current price: max(int64)
        priceUpdates.push(
            mockOracle.createPriceFeedUpdateData(
                mockPriceFeed, 0x7FFFFFFFFFFFFFFF, 10, -10, 0x7FFFFFFFFFFFFFFF, 10, publishTime, publishTime
            )
        );
        entrypoint.openTrade(t, ISettlement.TradeType.LIMIT, 1, priceUpdates);
        console.log("honey balance: %s", honey.balanceOf(trader));

        vm.roll(block.number + 2);
        vm.warp(block.timestamp + 10 seconds);
        publishTime += 10 seconds;

        // Trader opens up own limit order into a market position, current price: max(int64) - 1
        priceUpdates[0] = mockOracle.createPriceFeedUpdateData(
            mockPriceFeed, 0x7FFFFFFFFFFFFFFE, 10, -10, 0x7FFFFFFFFFFFFFFE, 10, publishTime, publishTime
        );
        entrypoint.executeLimitOrder(0, priceUpdates);
        console.log("honey balance: %s", honey.balanceOf(trader));

        // Now, price moves down to the trader's SL.
        vm.roll(block.number + 4);
        vm.warp(block.timestamp + 20 seconds);
        publishTime += 10 seconds;

        // Trader executes own order as SL is hit, current price: max(int64) - 2
        priceUpdates[0] = mockOracle.createPriceFeedUpdateData(
            mockPriceFeed, 0x7FFFFFFFFFFFFFFD, 10, -10, 0x7FFFFFFFFFFFFFFD, 10, publishTime, publishTime
        );
        entrypoint.executeLimitOrder(1, priceUpdates);
        console.log("honey balance: %s", honey.balanceOf(trader));

        vm.stopPrank();
    }

    function testOpenCloseSameBlock() external {
        vm.startPrank(trader, trader);

        // Initially within the last block (block.timestamp - 5 seconds), the price is 10.
        int64 initialPrice = 10e10;
        uint64 initialTime = uint64(block.timestamp - 4 seconds);
        priceUpdates.push(
            mockOracle.createPriceFeedUpdateData(
                mockPriceFeed, initialPrice, 10, -10, initialPrice, 10, initialTime, initialTime
            )
        );

        // Trader opens a market position at the initial price.
        IOrders.Trade memory t0 = IOrders.Trade(trader, 0, 0, 0, 10e18, initialPrice - 1, true, 100, 0, 0);
        entrypoint.openTrade(t0, ISettlement.TradeType.MARKET, 5e10, priceUpdates);
        assertEq(honey.balanceOf(trader), initialHoneyBalance - 10e18);

        // Then within the same block (block.timestamp - 5 seconds), the price moves to 11.
        int64 laterPrice = 11e10;
        uint64 laterTime = uint64(block.timestamp - 1 seconds);
        priceUpdates[0] = mockOracle.createPriceFeedUpdateData(
            mockPriceFeed, laterPrice, 10, -10, laterPrice, 10, laterTime, laterTime
        );

        // Trader tries to close the market position at the later price, within the same block.
        vm.expectRevert(BerpsErrors.InTimeout.selector);
        entrypoint.closeTradeMarket(0, priceUpdates);
        assertEq(honey.balanceOf(trader), initialHoneyBalance - 10e18); // Close does not settle.

        // 3 blocks later, trader tries to close the market position, price does not change.
        vm.roll(block.number + 3);
        vm.warp(block.timestamp + 15 seconds);
        entrypoint.closeTradeMarket(0, priceUpdates);
        assertEq(honey.balanceOf(trader), 1291e17); // Close does settle in profit.

        vm.stopPrank();
    }
}
