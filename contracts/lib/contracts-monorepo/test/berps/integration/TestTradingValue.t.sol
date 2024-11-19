// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { LibClone } from "solady/src/utils/LibClone.sol";

import "@pythnetwork/MockPyth.sol";

import "@mock/token/MockERC20.sol";

import { PayableMulticallable } from "transient-goodies/PayableMulticallable.sol";

import { IDelegatable, IEntrypoint } from "src/berps/core/v0/Entrypoint.sol";
import { IOrders } from "src/berps/core/v0/Orders.sol";
import { ISettlement } from "src/berps/core/v0/Settlement.sol";

import { BaseTradingTest } from "./BaseTradingTest.t.sol";

contract TestTradingValue is BaseTradingTest {
    address trader1 = address(0x1111);
    address user2 = address(0x4444);
    int64 oracle_price = 5e10;
    bytes[] priceUpdates;
    uint256 singleUpdateFee = 2;
    IOrders.Trade t = IOrders.Trade(trader1, 0, 0, 0, 10e18, oracle_price, true, 5, 0, 0);

    function setUp() public override {
        super.setUp();
        initializeTrading(singleUpdateFee);

        // Intialize & approve Honey.
        honey.mint(trader1, 50_000_000_000_000_000_000);
        vm.startPrank(trader1, trader1);
        honey.approve(address(orders), type(uint256).max);
        vm.stopPrank();

        // Set an oracle price that will be unchanged for these tests.
        uint64 publishTime = uint64(block.timestamp - 5 seconds);
        priceUpdates.push(
            mockOracle.createPriceFeedUpdateData(
                mockPriceFeed, oracle_price, 10, -10, oracle_price, 10, publishTime, publishTime
            )
        );
    }

    function testRefundNoMulticall() external {
        startHoax(trader1, trader1);

        // Trader 1 opens a trade, with an excess value of 3 wei.
        entrypoint.openTrade{ value: singleUpdateFee + 3 }(t, ISettlement.TradeType.MARKET, 5e10, priceUpdates);

        // Go forward 3 blocks.
        vm.roll(block.number + 3);
        vm.warp(block.timestamp + 15 seconds);

        // Trader 1 updates SL, with an excess value of 1 wei.
        entrypoint.updateSl{ value: singleUpdateFee + 1 }(0, oracle_price - 5e9, priceUpdates);

        // User 2 tries to refund any value, earns all 4 wei.
        startHoax(user2, user2, 1 ether);
        entrypoint.refundValue();
        assertEq(user2.balance, 1 ether + 1 + 3);
    }

    function testRefundWithMulticall() external {
        startHoax(trader1, trader1);

        // Trader1 opens a trade and opens another trade in a single multicall, with excess of 3 wei.
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IEntrypoint.openTrade, (t, ISettlement.TradeType.MARKET, 5e10, priceUpdates));
        data[1] = abi.encodeCall(IEntrypoint.openTrade, (t, ISettlement.TradeType.MARKET, 5e10, priceUpdates));

        // Send with 3 extra wei.
        entrypoint.multicall{ value: 2 * singleUpdateFee + 3 }(true, data);

        // Trader 1 updates SL, with an excess value of 1 wei.
        entrypoint.updateSl{ value: singleUpdateFee + 1 }(0, oracle_price - 5e9, priceUpdates);

        // User 2 tries to refund any value, earns 4 wei.
        startHoax(user2, user2, 1 ether);
        entrypoint.refundValue();
        assertEq(user2.balance, 1 ether + 2 * singleUpdateFee);
    }

    function testRefundInMulticall() external {
        startHoax(trader1, trader1, 1 ether);

        // Trader1 opens a trade, opens another trade, and refunds excess value in a single multicall.
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(IEntrypoint.openTrade, (t, ISettlement.TradeType.MARKET, 5e10, priceUpdates));
        data[1] = abi.encodeCall(IEntrypoint.openTrade, (t, ISettlement.TradeType.MARKET, 5e10, priceUpdates));
        data[2] = abi.encodeCall(IDelegatable.refundValue, ());

        // Send with 5 extra wei.
        entrypoint.multicall{ value: 2 * singleUpdateFee + 5 }(true, data);

        // Trader 1 only lost the 4 wei for price updates and was refunded the excess of 5 wei.
        assertEq(trader1.balance, 1 ether - 2 * singleUpdateFee);
    }

    function testRefundForDelegate() external {
        // Trader1 sets user 2 as delegate.
        vm.prank(trader1, trader1);
        entrypoint.setDelegate(user2);

        startHoax(user2, user2, 1 ether);

        // User 2 opens a trade for trader 1, with an excess value of 3 wei.
        entrypoint.delegatedAction{ value: singleUpdateFee + 3 }(
            trader1, abi.encodeCall(IEntrypoint.openTrade, (t, ISettlement.TradeType.MARKET, 5e10, priceUpdates))
        );
        assertEq(address(entrypoint).balance, 3);

        // If user 2 refunds value, it goes to user 2 and not trader 1.
        entrypoint.refundValue();
        assertEq(user2.balance, 1 ether - singleUpdateFee); // only lost 2 wei for the update.
    }

    function testRefundForDelegateWithMulticall() external {
        // Trader1 sets user 2 as delegate.
        vm.prank(trader1, trader1);
        entrypoint.setDelegate(user2);

        startHoax(user2, user2, 1 ether);

        // User 2 opens a trade, opens another trade for trader 1, and refunds excess value in a single multicall.
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(IEntrypoint.openTrade, (t, ISettlement.TradeType.MARKET, 5e10, priceUpdates));
        data[1] = abi.encodeCall(IEntrypoint.openTrade, (t, ISettlement.TradeType.MARKET, 5e10, priceUpdates));
        data[2] = abi.encodeCall(IDelegatable.refundValue, ());

        // User 2 sends with 5 extra wei.
        entrypoint.delegatedAction{ value: 2 * singleUpdateFee + 5 }(
            trader1, abi.encodeCall(PayableMulticallable.multicall, (true, data))
        );

        // The refund goes to user 2 and not trader 1.
        assertEq(user2.balance, 1 ether - 2 * singleUpdateFee); // only lost 4 wei for the update.
    }
}
