// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { IOrders } from "src/berps/interfaces/v0/IOrders.sol";
import { ISettlement } from "src/berps/interfaces/v0/ISettlement.sol";

import { BaseTradingTest } from "./BaseTradingTest.t.sol";

contract TestTradingFee is BaseTradingTest {
    int64 oracle_price = 1e10; // price of 1
    bytes[] priceUpdates;
    address user1 = address(0x1111);

    function setUp() public override {
        super.setUp();
        initializeTrading(0); // Oracle update fee is 0 for these tests.

        honey.mint(user1, 50e18);
        vm.prank(user1, user1);
        honey.approve(address(orders), type(uint256).max);
        vm.stopPrank();
    }

    function testTradingCloseMarket() external {
        vm.startPrank(user1, user1);

        // Set oracle price.
        uint64 publishTime = uint64(block.timestamp - 5 seconds);
        priceUpdates.push(
            mockOracle.createPriceFeedUpdateData(
                mockPriceFeed, oracle_price, 10, -10, oracle_price, 10, publishTime, publishTime
            )
        );

        // User opens a limit order.
        console.log("honey balance: %s", honey.balanceOf(user1));
        IOrders.Trade memory t0 = IOrders.Trade(
            user1,
            0,
            0,
            0,
            10e18,
            oracle_price - 1,
            true,
            100,
            oracle_price + 5e8, // +%5
            oracle_price - 5e8 // -%5
        );
        entrypoint.openTrade(t0, ISettlement.TradeType.LIMIT, 0, priceUpdates);

        // Go forward 3 blocks.
        vm.roll(block.number + 3);
        vm.warp(block.timestamp + 15 seconds);
        publishTime += 15 seconds;

        // Set current oracle price to decrease by 1 to target.
        oracle_price -= 1;
        priceUpdates[0] = mockOracle.createPriceFeedUpdateData(
            mockPriceFeed, oracle_price, 10, -10, oracle_price, 10, publishTime, publishTime
        );

        // User opens limit order into a position.
        entrypoint.executeLimitOrder(0, priceUpdates);

        // Go forward 3 blocks.
        vm.roll(block.number + 6);
        vm.warp(block.timestamp + 30 seconds);
        publishTime += 15 seconds;

        // Set current oracle price to increase by 4%.
        oracle_price += 4e8;
        priceUpdates[0] = mockOracle.createPriceFeedUpdateData(
            mockPriceFeed, oracle_price, 10, -10, oracle_price, 10, publishTime, publishTime
        );

        // User closes the position.
        entrypoint.closeTradeMarket(1, priceUpdates);
        console.log("honey balance: %s", honey.balanceOf(user1));
        vm.stopPrank();
    }

    function testTradingCloseTP() external {
        vm.startPrank(user1, user1);

        // Set oracle price.
        uint64 publishTime = uint64(block.timestamp - 5 seconds);
        priceUpdates.push(
            mockOracle.createPriceFeedUpdateData(
                mockPriceFeed, oracle_price, 10, -10, oracle_price, 10, publishTime, publishTime
            )
        );

        // User opens a limit order.
        console.log("honey balance: %s", honey.balanceOf(user1));
        IOrders.Trade memory t0 = IOrders.Trade(
            user1,
            0,
            0,
            0,
            10e18,
            oracle_price - 1,
            true,
            100,
            oracle_price + 1e9, // +%10
            oracle_price - 1e9 // -%10
        );
        entrypoint.openTrade(t0, ISettlement.TradeType.LIMIT, 1, priceUpdates);

        // Go forward 3 blocks.
        vm.roll(block.number + 3);
        vm.warp(block.timestamp + 15 seconds);
        publishTime += 15 seconds;

        // Set current oracle price to decrease by 1 to target.
        oracle_price -= 1;
        priceUpdates[0] = mockOracle.createPriceFeedUpdateData(
            mockPriceFeed, oracle_price, 10, -10, oracle_price, 10, publishTime, publishTime
        );

        // User opens limit order into a position.
        entrypoint.executeLimitOrder(0, priceUpdates);

        // Go forward 3 blocks.
        vm.roll(block.number + 6);
        vm.warp(block.timestamp + 30 seconds);
        publishTime += 15 seconds;

        // User updates their TP to the next price increase.
        entrypoint.updateTp(1, oracle_price + 5e8);

        // Go forward 3 blocks.
        vm.roll(block.number + 9);
        vm.warp(block.timestamp + 45 seconds);
        publishTime += 15 seconds;

        // Set current oracle price to increase by 5%.
        oracle_price += 5e8 + 1;
        priceUpdates[0] = mockOracle.createPriceFeedUpdateData(
            mockPriceFeed, oracle_price, 10, -10, oracle_price, 10, publishTime, publishTime
        );

        // User closes position with TP (as a bot executor).
        entrypoint.executeLimitOrder(1, priceUpdates);
        console.log("honey balance: %s", honey.balanceOf(user1));
        vm.stopPrank();
    }

    function testTradingCloseSL() external {
        vm.startPrank(user1, user1);

        // Set oracle price.
        uint64 publishTime = uint64(block.timestamp - 5 seconds);
        priceUpdates.push(
            mockOracle.createPriceFeedUpdateData(
                mockPriceFeed, oracle_price, 10, -10, oracle_price, 10, publishTime, publishTime
            )
        );

        // User opens a limit order.
        console.log("honey balance: %s", honey.balanceOf(user1));
        IOrders.Trade memory t0 = IOrders.Trade(
            user1,
            0,
            0,
            0,
            10_000_000_000_000_000_000,
            oracle_price + 1,
            false,
            100,
            oracle_price - 1e9, // +%10
            oracle_price + 1e9 // -%10
        );
        entrypoint.openTrade(t0, ISettlement.TradeType.LIMIT, 1, priceUpdates);

        // Go forward 3 blocks.
        vm.roll(block.number + 3);
        vm.warp(block.timestamp + 15 seconds);
        publishTime += 15 seconds;

        // Set current oracle price to decrease by 1 to target.
        oracle_price += 1;
        priceUpdates[0] = mockOracle.createPriceFeedUpdateData(
            mockPriceFeed, oracle_price, 10, -10, oracle_price, 10, publishTime, publishTime
        );

        // User opens limit order into a position.
        entrypoint.executeLimitOrder(0, priceUpdates);

        // Go forward 3 blocks.
        vm.roll(block.number + 6);
        vm.warp(block.timestamp + 30 seconds);
        publishTime += 15 seconds;

        // User updates their SL, but price stays the same.
        priceUpdates[0] = mockOracle.createPriceFeedUpdateData(
            mockPriceFeed, oracle_price, 10, -10, oracle_price, 10, publishTime, publishTime
        );
        entrypoint.updateSl(1, oracle_price + 5e7, priceUpdates);

        // Go forward 3 blocks.
        vm.roll(block.number + 9);
        vm.warp(block.timestamp + 45 seconds);
        publishTime += 15 seconds;

        // Set current oracle price to increase by 0.5%.
        oracle_price += 5e7 + 1;
        priceUpdates[0] = mockOracle.createPriceFeedUpdateData(
            mockPriceFeed, oracle_price, 10, -10, oracle_price, 10, publishTime, publishTime
        );

        // User closes position with TP (as a bot executor).
        entrypoint.executeLimitOrder(1, priceUpdates);
        console.log("honey balance: %s", honey.balanceOf(user1));
        vm.stopPrank();
    }
}
