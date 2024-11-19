// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { LibClone } from "solady/src/utils/LibClone.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@mock/token/MockERC20.sol";

import "src/berps/core/v0/Orders.sol";

contract TestOrders is Test {
    Orders orders;
    address gov = makeAddr("gov");
    address honey;
    address markets = makeAddr("markets");
    address vault = makeAddr("vault");
    address entrypoint = makeAddr("entrypoint");
    address settlement = makeAddr("settlement");
    address referrals = makeAddr("referrals");
    address trader = makeAddr("trader");

    function setUp() public {
        orders = Orders(LibClone.deployERC1967(address(new Orders())));
        honey = address(new MockERC20());
        orders.initialize(honey, gov, markets, vault, entrypoint, settlement, referrals);
    }

    function testStoreTrade() public {
        vm.startPrank(settlement);
        IOrders.Trade memory trade = IOrders.Trade({
            trader: trader,
            pairIndex: 1,
            index: 0,
            initialPosToken: 1e18,
            positionSizeHoney: 1e18,
            openPrice: 10_000,
            buy: true,
            leverage: 10,
            tp: 12_000,
            sl: 8000
        });
        IOrders.TradeInfo memory tradeInfo =
            IOrders.TradeInfo({ tokenPriceHoney: 10_000, openInterestHoney: 1e18 * 10 });

        orders.storeTrade(trade, tradeInfo);

        IOrders.Trade memory storedTrade = orders.getOpenTrade(trade.index);
        assertEq(storedTrade.trader, trader);
        assertEq(storedTrade.pairIndex, 1);
        assertEq(storedTrade.initialPosToken, 1e18);
        assertEq(storedTrade.positionSizeHoney, 1e18);
        assertEq(storedTrade.openPrice, 10_000);
        assertEq(storedTrade.buy, true);
        assertEq(storedTrade.leverage, 10);
        assertEq(storedTrade.tp, 12_000);
        assertEq(storedTrade.sl, 8000);
    }

    function testUnregisterTrade() public {
        vm.startPrank(settlement);
        IOrders.Trade memory trade = IOrders.Trade({
            trader: trader,
            pairIndex: 1,
            index: 0,
            initialPosToken: 1e18,
            positionSizeHoney: 1e18,
            openPrice: 10_000,
            buy: true,
            leverage: 10,
            tp: 12_000,
            sl: 8000
        });
        IOrders.TradeInfo memory tradeInfo =
            IOrders.TradeInfo({ tokenPriceHoney: 10_000, openInterestHoney: 1e18 * 10 });

        orders.storeTrade(trade, tradeInfo);

        assertEq(orders.getOpenTradesCount(trader, 1), 1);

        orders.unregisterTrade(trade.index);

        assertEq(orders.getOpenTradesCount(trader, 1), 0);

        IOrders.Trade memory storedTrade = orders.getOpenTrade(trade.index);
        assertEq(storedTrade.trader, address(0));

        assertEq(orders.getOpenTrade(trade.index).leverage, 0);
    }

    function testGetOpenTrades() public {
        vm.startPrank(settlement);
        IOrders.Trade memory trade1 = IOrders.Trade({
            trader: trader,
            pairIndex: 1,
            index: 0,
            initialPosToken: 1e18,
            positionSizeHoney: 1e18,
            openPrice: 10_000,
            buy: true,
            leverage: 10,
            tp: 12_000,
            sl: 8000
        });
        IOrders.Trade memory trade2 = IOrders.Trade({
            trader: trader,
            pairIndex: 1,
            index: 1,
            initialPosToken: 2e18,
            positionSizeHoney: 2e18,
            openPrice: 11_000,
            buy: false,
            leverage: 20,
            tp: 13_000,
            sl: 9000
        });
        IOrders.TradeInfo memory tradeInfo =
            IOrders.TradeInfo({ tokenPriceHoney: 10_000, openInterestHoney: 1e18 * 10 });

        orders.storeTrade(trade1, tradeInfo);
        orders.storeTrade(trade2, tradeInfo);

        IOrders.Trade[] memory openTrades = orders.getOpenTrades(1, 2);
        assertEq(openTrades.length, 2);
        assertEq(openTrades[0].trader, trader);
        assertEq(openTrades[1].trader, trader);
    }

    function testStoreOpenLimitOrder() public {
        vm.startPrank(settlement);
        IOrders.OpenLimitOrder memory order = IOrders.OpenLimitOrder({
            trader: trader,
            pairIndex: 1,
            index: 0,
            positionSize: 1e18,
            buy: true,
            leverage: 10,
            tp: 12_000,
            sl: 8000,
            minPrice: 9500,
            maxPrice: 10_500
        });

        orders.storeOpenLimitOrder(order);

        IOrders.OpenLimitOrder memory storedOrder = orders.getOpenLimitOrder(order.index);
        assertEq(storedOrder.trader, trader);
        assertEq(storedOrder.pairIndex, 1);
        assertEq(storedOrder.positionSize, 1e18);
        assertEq(storedOrder.buy, true);
        assertEq(storedOrder.leverage, 10);
        assertEq(storedOrder.tp, 12_000);
        assertEq(storedOrder.sl, 8000);
        assertEq(storedOrder.minPrice, 9500);
        assertEq(storedOrder.maxPrice, 10_500);
    }

    function testUnregisterOpenLimitOrder() public {
        vm.startPrank(settlement);
        IOrders.OpenLimitOrder memory order = IOrders.OpenLimitOrder({
            trader: trader,
            pairIndex: 1,
            index: 0,
            positionSize: 1e18,
            buy: true,
            leverage: 10,
            tp: 12_000,
            sl: 8000,
            minPrice: 9500,
            maxPrice: 10_500
        });

        orders.storeOpenLimitOrder(order);

        assertEq(orders.getOpenLimitOrdersCount(trader, 1), 1);

        orders.unregisterOpenLimitOrder(order.index);

        assertEq(orders.getOpenLimitOrdersCount(trader, 1), 0);

        IOrders.OpenLimitOrder memory storedOrder = orders.getOpenLimitOrder(order.index);
        assertEq(storedOrder.trader, address(0));

        assertEq(orders.getOpenLimitOrder(order.index).leverage, 0);
    }

    function testGetOpenLimitOrders() public {
        vm.startPrank(settlement);
        IOrders.OpenLimitOrder memory order1 = IOrders.OpenLimitOrder({
            trader: trader,
            pairIndex: 1,
            index: 0,
            positionSize: 1e18,
            buy: true,
            leverage: 10,
            tp: 12_000,
            sl: 8000,
            minPrice: 9500,
            maxPrice: 10_500
        });
        IOrders.OpenLimitOrder memory order2 = IOrders.OpenLimitOrder({
            trader: trader,
            pairIndex: 1,
            index: 1,
            positionSize: 2e18,
            buy: false,
            leverage: 20,
            tp: 13_000,
            sl: 9000,
            minPrice: 10_000,
            maxPrice: 11_000
        });

        orders.storeOpenLimitOrder(order1);
        orders.storeOpenLimitOrder(order2);

        IOrders.OpenLimitOrder[] memory openOrders = orders.getOpenLimitOrders(1, 2);
        assertEq(openOrders.length, 2);
        assertEq(openOrders[0].trader, trader);
        assertEq(openOrders[1].trader, trader);
    }
}
