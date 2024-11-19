// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { console2 } from "forge-std/Script.sol";

import { BaseScript } from "../base/Base.s.sol";

import { Addresses } from "./Addresses.sol";

import { PythFeeds } from "../../src/berps/utils/PythFeeds.sol";
import { Entrypoint } from "../../src/berps/core/v0/Entrypoint.sol";
import { Settlement } from "../../src/berps/core/v0/Settlement.sol";
import { FeesAccrued, IFeesAccrued } from "../../src/berps/core/v0/FeesAccrued.sol";
import { Vault } from "../../src/berps/core/v0/Vault.sol";
import { FeesMarkets } from "../../src/berps/core/v0/FeesMarkets.sol";
import { Markets, IMarkets } from "../../src/berps/core/v0/Markets.sol";
import { Orders } from "../../src/berps/core/v0/Orders.sol";

/// @notice UpdateGov updates the gov accounts in the following contracts:
///  1. `manager` in Vault
///  2. `ownership` in Vault
///  3. `manager` in FeesMarkets
///  4. `gov` in Orders
/// @dev msg.sender must be the existing gov account.
/// @dev `newGov` must be set!
contract UpdateGov is BaseScript {
    function run() public broadcast {
        Vault vault = Addresses.DEPLOYER.vaultProxy();
        FeesMarkets feesMarkets = Addresses.DEPLOYER.feesMarketsProxy();
        Orders orders = Addresses.DEPLOYER.ordersProxy();

        address newGov = address(0);

        // Update the Vault contract.
        vault.updateManager(newGov);
        console2.log("New Vault Manager", newGov);
        vault.transferOwnership(newGov);
        console2.log("New Vault Ownership", newGov);

        // Update the FeesMarkets contract.
        feesMarkets.setManager(newGov);
        console2.log("New FeesMarkets Manager", newGov);

        // Update the Orders contract.
        orders.setGov(newGov);
        console2.log("New Orders Gov", newGov);
    }
}

/// @notice Used to update the implementation of the FeesAccrued contract.
/// @dev replace the call to `upgradeToAndCall` with `intitializeV_` if a reinitialize function is needed.
contract UpdateFeesAccrued is BaseScript {
    function run() public broadcast {
        address newFeesAccruedImpl = address(new FeesAccrued());
        console2.log("New FeesAccrued Implementation Contract", newFeesAccruedImpl);

        FeesAccrued feesAccruedProxy = FeesAccrued(Addresses.DEPLOYER.feesAccruedProxy());
        feesAccruedProxy.upgradeToAndCall(newFeesAccruedImpl, new bytes(0));
    }
}

/// @notice Used to update the implementation of the Trading contracts (Entrypoint and Settlement).
/// @dev replace the call to `upgradeToAndCall` with `intitializeV_` if a reinitialize function is needed.
contract UpdateTrading is BaseScript {
    function run() public broadcast {
        Entrypoint entrypointProxy = Entrypoint(Addresses.DEPLOYER.entrypointProxy());

        // Pause trading during upgrade.
        entrypointProxy.pause();

        // Deploy new entrypoint implementation and upgrade.
        address newEntrypointImpl = address(new Entrypoint());
        console2.log("New Entrypoint Implementation Contract", newEntrypointImpl);
        entrypointProxy.upgradeToAndCall(newEntrypointImpl, new bytes(0));

        // Deploy new settlement implementation and upgrade.
        address newSettlementImpl = address(new Settlement());
        console2.log("New Settlement Implementation Contract", newSettlementImpl);
        Settlement settlementProxy = Settlement(Addresses.DEPLOYER.settlementProxy());
        settlementProxy.upgradeToAndCall(newSettlementImpl, new bytes(0));

        // Unpause trading after upgrade.
        entrypointProxy.pause();
    }
}

/// @notice Used to update the implementation of the Settlement contract.
/// @dev replace the call to `upgradeToAndCall` with `intitializeV_` if a reinitialize function is needed.
contract UpdateSettlement is BaseScript {
    function run() public broadcast {
        // Deploy new settlement implementation and upgrade.
        address newSettlementImpl = address(new Settlement());
        console2.log("New Settlement Implementation Contract", newSettlementImpl);
        Settlement settlementProxy = Settlement(Addresses.DEPLOYER.settlementProxy());
        settlementProxy.upgradeToAndCall(newSettlementImpl, new bytes(0));
    }
}

/// @notice Used to update the implementation of the Settlement contract.
/// @dev replace the call to `upgradeToAndCall` with `intitializeV_` if a reinitialize function is needed.
contract UpdateVault is BaseScript {
    function run() public broadcast {
        // Deploy new vault implementation and upgrade.
        address newVaultImpl = address(new Vault());
        console2.log("New Vault Implementation Contract", newVaultImpl);
        Vault vaultProxy = Vault(Addresses.DEPLOYER.vaultProxy());
        vaultProxy.upgradeToAndCall(newVaultImpl, new bytes(0));
    }
}

contract UpdatePair is BaseScript {
    function run() public broadcast {
        Markets markets = Addresses.DEPLOYER.marketsProxy();
        FeesAccrued feesAccrued = Addresses.DEPLOYER.feesAccruedProxy();

        // Build the feed.
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = PythFeeds.ATOM_USD;
        ids[1] = PythFeeds.USDC_USD;
        IMarkets.Feed memory feed2 = IMarkets.Feed({
            ids: ids,
            feedCalculation: IMarkets.FeedCalculation.TRIANGULAR,
            useConfSpread: true, // protect the house from unusual price volatility
            confThresholdP: 0.25 * 1e10, // 0.25% (1e10), generally Pyth returns a conf <= 0.1%
            useEma: false // not necessary since confidence threshold is set
         });

        // Build the pair.
        IMarkets.Pair memory pair2 =
            IMarkets.Pair({ from: "ATOM", to: "USDC", feed: feed2, groupIndex: 0, feeIndex: 0 });

        IMarkets.Fee memory fee2 = IMarkets.Fee({
            name: "ATOM",
            openFeeP: 1e9, // 0.1%
            closeFeeP: 1e9, // 0.1%
            limitOrderFeeP: 5e8, // 0.05%
            minLevPosHoney: 10e18 // 10 HONEY
         });

        // Add the fee.
        markets.updateFee(2, fee2);

        // Add the pair.
        markets.updatePair(2, pair2);

        IFeesAccrued.PairParams memory pp = IFeesAccrued.PairParams({
            groupIndex: 0,
            baseBorrowAPR: 100 * 1e10 // 100% Base Borrowing APR
         });
        feesAccrued.setPairParams(2, pp);
    }
}
