// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IFeesAccrued } from "../../src/berps/interfaces/v0/IFeesAccrued.sol";
import { IMarkets } from "../../src/berps/interfaces/v0/IMarkets.sol";

import { Markets } from "../../src/berps/core/v0/Markets.sol";
import { Orders } from "../../src/berps/core/v0/Orders.sol";
import { FeesAccrued } from "../../src/berps/core/v0/FeesAccrued.sol";
import { PythFeeds } from "../../src/berps/utils/PythFeeds.sol";

import { BaseScript } from "../base/Base.s.sol";

import { Addresses } from "./Addresses.sol";

contract GlobalSettings is BaseScript {
    function run() public broadcast {
        Markets markets = Addresses.DEPLOYER.marketsProxy();
        Orders orders = Addresses.DEPLOYER.ordersProxy();

        // Set max trades per pair (for all pairs).
        orders.setMaxTradesPerPair(5); // 5 trades per pair per trader

        // Build the group.
        IMarkets.Group memory group =
            IMarkets.Group({ name: "crypto", minLeverage: 2, maxLeverage: 100, maxCollateralP: 5 });

        // Add the group.
        markets.addGroup(group);

        // TODO: Add a group (index of 1 or above) for FeesAccrued?
    }
}

contract BTCUSDCPair is BaseScript {
    function run() public broadcast {
        Markets markets = Addresses.DEPLOYER.marketsProxy();
        Orders orders = Addresses.DEPLOYER.ordersProxy();
        FeesAccrued feesAccrued = Addresses.DEPLOYER.feesAccruedProxy();

        // Build the feed.
        bytes32[] memory ids = new bytes32[](3);
        ids[0] = PythFeeds.HONEY_USD;
        ids[1] = PythFeeds.BTC_USD;
        ids[2] = PythFeeds.USDC_USD;
        IMarkets.Feed memory feed = IMarkets.Feed({
            ids: ids,
            feedCalculation: IMarkets.FeedCalculation.TRIANGULAR,
            useConfSpread: true, // protect the house from unusual price volatility
            confThresholdP: 0.25 * 1e10, // 0.25% (1e10), generally Pyth returns a conf <= 0.1%
            useEma: false // not necessary since confidence threshold is set
         });

        // Build the pair.
        IMarkets.Pair memory pair = IMarkets.Pair({ from: "BTC", to: "USDC", feed: feed, groupIndex: 0, feeIndex: 0 });

        IMarkets.Fee memory fee = IMarkets.Fee({
            name: "BTC",
            openFeeP: 1e9, // 0.1%
            closeFeeP: 1e9, // 0.1%
            limitOrderFeeP: 5e8, // 0.05%
            minLevPosHoney: 10e18 // 10 HONEY
         });

        // Add the fee.
        markets.addFee(fee);

        // Add the pair.
        markets.addPair(pair);

        // set max open interest HONEY
        orders.setMaxOpenInterestHoney(0, 5e25);

        IFeesAccrued.PairParams memory pp = IFeesAccrued.PairParams({
            groupIndex: 0,
            baseBorrowAPR: 500 * 1e10 // 500% Base Borrowing APR
         });
        feesAccrued.setPairParams(0, pp);
    }
}

contract ETHUSDCPair is BaseScript {
    function run() public broadcast {
        Markets markets = Addresses.DEPLOYER.marketsProxy();
        Orders orders = Addresses.DEPLOYER.ordersProxy();
        FeesAccrued feesAccrued = Addresses.DEPLOYER.feesAccruedProxy();

        // Build the feed.
        bytes32[] memory ids = new bytes32[](3);
        ids[0] = PythFeeds.HONEY_USD;
        ids[1] = PythFeeds.ETH_USD;
        ids[2] = PythFeeds.USDC_USD;
        IMarkets.Feed memory feed = IMarkets.Feed({
            ids: ids,
            feedCalculation: IMarkets.FeedCalculation.TRIANGULAR,
            useConfSpread: true, // protect the house from unusual price volatility
            confThresholdP: 0.25 * 1e10, // 0.25% (1e10), generally Pyth returns a conf <= 0.1%
            useEma: false // not necessary since confidence threshold is set
         });

        // Build the pair.
        IMarkets.Pair memory pair = IMarkets.Pair({ from: "ETH", to: "USDC", feed: feed, groupIndex: 0, feeIndex: 1 });

        IMarkets.Fee memory fee = IMarkets.Fee({
            name: "ETH",
            openFeeP: 1e9, // 0.1%
            closeFeeP: 1e9, // 0.1%
            limitOrderFeeP: 5e8, // 0.05%
            minLevPosHoney: 10e18 // 10 HONEY
         });

        // Add the fee.
        markets.addFee(fee);

        // Add the pair.
        markets.addPair(pair);

        // set max open interest HONEY
        orders.setMaxOpenInterestHoney(1, 5e25);

        IFeesAccrued.PairParams memory pp = IFeesAccrued.PairParams({
            groupIndex: 0,
            baseBorrowAPR: 500 * 1e10 // 500% Base Borrowing APR
         });
        feesAccrued.setPairParams(1, pp);
    }
}

contract ATOMUSDCPair is BaseScript {
    function run() public broadcast {
        Markets markets = Addresses.DEPLOYER.marketsProxy();
        Orders orders = Addresses.DEPLOYER.ordersProxy();
        FeesAccrued feesAccrued = Addresses.DEPLOYER.feesAccruedProxy();

        // Build the feed.
        bytes32[] memory ids = new bytes32[](3);
        ids[0] = PythFeeds.HONEY_USD;
        ids[1] = PythFeeds.ATOM_USD;
        ids[2] = PythFeeds.USDC_USD;
        IMarkets.Feed memory feed = IMarkets.Feed({
            ids: ids,
            feedCalculation: IMarkets.FeedCalculation.TRIANGULAR,
            useConfSpread: true, // protect the house from unusual price volatility
            confThresholdP: 0.25 * 1e10, // 0.25% (1e10), generally Pyth returns a conf <= 0.1%
            useEma: false // not necessary since confidence threshold is set
         });

        // Build the pair.
        IMarkets.Pair memory pair = IMarkets.Pair({ from: "ATOM", to: "USDC", feed: feed, groupIndex: 0, feeIndex: 2 });

        IMarkets.Fee memory fee = IMarkets.Fee({
            name: "ATOM",
            openFeeP: 1e9, // 0.1%
            closeFeeP: 1e9, // 0.1%
            limitOrderFeeP: 5e8, // 0.05%
            minLevPosHoney: 10e18 // 10 HONEY
         });

        // Add the fee.
        markets.addFee(fee);

        // Add the pair.
        markets.addPair(pair);

        // set max open interest HONEY
        orders.setMaxOpenInterestHoney(2, 5e25);

        IFeesAccrued.PairParams memory pp = IFeesAccrued.PairParams({
            groupIndex: 0,
            baseBorrowAPR: 500 * 1e10 // 500% Base Borrowing APR
         });
        feesAccrued.setPairParams(2, pp);
    }
}

contract TIAUSDCPair is BaseScript {
    function run() public broadcast {
        Markets markets = Addresses.DEPLOYER.marketsProxy();
        Orders orders = Addresses.DEPLOYER.ordersProxy();
        FeesAccrued feesAccrued = Addresses.DEPLOYER.feesAccruedProxy();

        // Build the feed.
        bytes32[] memory ids = new bytes32[](3);
        ids[0] = PythFeeds.HONEY_USD;
        ids[1] = PythFeeds.TIA_USD;
        ids[2] = PythFeeds.USDC_USD;
        IMarkets.Feed memory feed = IMarkets.Feed({
            ids: ids,
            feedCalculation: IMarkets.FeedCalculation.TRIANGULAR,
            useConfSpread: true, // protect the house from unusual price volatility
            confThresholdP: 0.25 * 1e10, // 0.25% (1e10), generally Pyth returns a conf <= 0.1%
            useEma: false // not necessary since confidence threshold is set
         });

        // Build the pair.
        IMarkets.Pair memory pair = IMarkets.Pair({ from: "TIA", to: "USDC", feed: feed, groupIndex: 0, feeIndex: 3 });

        IMarkets.Fee memory fee = IMarkets.Fee({
            name: "TIA",
            openFeeP: 1e9, // 0.1%
            closeFeeP: 1e9, // 0.1%
            limitOrderFeeP: 5e8, // 0.05%
            minLevPosHoney: 10e18 // 10 HONEY
         });

        // Add the fee.
        markets.addFee(fee);

        // Add the pair.
        markets.addPair(pair);

        // set max open interest HONEY
        orders.setMaxOpenInterestHoney(3, 5e25);

        IFeesAccrued.PairParams memory pp = IFeesAccrued.PairParams({
            groupIndex: 0,
            baseBorrowAPR: 500 * 1e10 // 500% Base Borrowing APR
         });
        feesAccrued.setPairParams(3, pp);
    }
}
