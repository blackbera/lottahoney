// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { console2 } from "forge-std/Script.sol";

// Contracts
import { FeesAccrued } from "../../src/berps/core/v0/FeesAccrued.sol";
import { Vault, IVault } from "../../src/berps/core/v0/Vault.sol";
import { VaultSafetyModule } from "../../src/berps/core/v0/VaultSafetyModule.sol";
import { FeesMarkets } from "../../src/berps/core/v0/FeesMarkets.sol";
import { Markets } from "../../src/berps/core/v0/Markets.sol";
import { Referrals } from "../../src/berps/core/v0/Referrals.sol";
import { Entrypoint } from "../../src/berps/core/v0/Entrypoint.sol";
import { Settlement } from "../../src/berps/core/v0/Settlement.sol";
import { Orders } from "../../src/berps/core/v0/Orders.sol";

import { BerpsDeployer, Implementations, Salts } from "../../src/berps/deploy/v0/BerpsDeployer.sol";

import { BaseScript } from "../base/Base.s.sol";

import { Addresses } from "./Addresses.sol";

contract SetupDeployment is BaseScript {
    function run() public broadcast {
        deployDeployer();
    }

    /// @dev Set salts for Berps proxy contracts here!
    function deployDeployer() internal {
        Implementations memory _impls;

        _impls.feesAccrued = address(new FeesAccrued());
        console2.log("FeesAccrued Impl deployed at:", _impls.feesAccrued);

        _impls.vault = address(new Vault());
        console2.log("Vault Impl deployed at:", _impls.vault);

        _impls.feesMarkets = address(new FeesMarkets());
        console2.log("FeesMarkets Impl deployed at:", _impls.feesMarkets);

        _impls.markets = address(new Markets());
        console2.log("Markets Impl deployed at:", _impls.markets);

        _impls.referrals = address(new Referrals());
        console2.log("Referrals Impl deployed at:", _impls.referrals);

        _impls.entrypoint = address(new Entrypoint());
        console2.log("Entrypoint Impl deployed at:", _impls.entrypoint);

        _impls.settlement = address(new Settlement());
        console2.log("Settlement Impl deployed at:", _impls.settlement);

        _impls.orders = address(new Orders());
        console2.log("Orders Impl deployed at:", _impls.orders);

        _impls.vaultSafetyModule = address(new VaultSafetyModule());
        console2.log("VaultSafetyModule Impl deployed at:", _impls.vaultSafetyModule);

        // TODO: choose better salts?
        Salts memory _salts = Salts(1, 2, 3, 4, 5, 6, 7, 8, 9);

        BerpsDeployer deployer = new BerpsDeployer(_impls, _salts);
        console2.log("BerpsDeployer deployed at:", address(deployer));
    }
}

/// @dev Ensure the Addresses library has a non-zero address set for `DEPLOYER`!
contract DeployAndInitialize is BaseScript {
    function run() public broadcast {
        deployAndInitializeContracts(Addresses.DEPLOYER);
    }

    /// @notice Each contract is atomically deployed and initialized to prevent front-running attacks.
    /// @dev Ensure Honey is set here!
    function deployAndInitializeContracts(BerpsDeployer deployer) internal {
        address _honey = address(0);

        deployer.deployFeesAccrued();
        console2.log("FeesAccrued Proxy deployed at:", address(deployer.feesAccruedProxy()));

        deployVault(deployer, _honey);
        console2.log("Vault Proxy deployed at:", address(deployer.vaultProxy()));

        deployFeesMarkets(deployer);
        console2.log("FeesMarkets Proxy deployed at:", address(deployer.feesMarketsProxy()));

        deployer.deployMarkets();
        console2.log("Markets Proxy deployed at:", address(deployer.marketsProxy()));

        deployReferrals(deployer);
        console2.log("Referrals Proxy deployed at:", address(deployer.referralsProxy()));

        deployEntrypoint(deployer);
        console2.log("Entrypoint Proxy deployed at:", address(deployer.entrypointProxy()));

        deploySettlement(deployer, _honey);
        console2.log("Settlement Proxy deployed at:", address(deployer.settlementProxy()));

        deployOrders(deployer, _honey);
        console2.log("Orders Proxy deployed at:", address(deployer.ordersProxy()));

        deployVaultSafetyModule(deployer, _honey);
        console2.log("VaultSafetyModule Proxy deployed at:", address(deployer.vaultSafetyModuleProxy()));
    }

    /// @dev Set parameters here!
    function deployVault(BerpsDeployer deployer, address _honey) internal {
        IVault.ContractAddresses memory _contractAddresses = IVault.ContractAddresses({
            asset: _honey,
            owner: msg.sender,
            manager: msg.sender,
            pnlHandler: msg.sender, // NOTE: overriden to the settlement contract.
            safetyModule: address(0) // NOTE: overriden with the vault safety module contract.
         });
        IVault.Params memory params = IVault.Params({
            _maxDailyAccPnlDelta: 1e18, // max daily PnL per bHoney of 1 Honey
            _withdrawLockThresholdsPLow: 10e18, // 10% (1e18)
            _withdrawLockThresholdsPHigh: 20e18, // 20% (1e18)
            _maxSupplyIncreaseDailyP: 2e18, // 2% (1e18)
            _epochLength: 12 hours, // 12 hours epochs
            _minRecollatP: 130e18, // 130% (1e18)
            _safeMinSharePrice: 1.1e18 // 1.1 Honey/bHoney (1e18)
         });

        deployer.deployVault(
            "bHoney", // ERC20 name
            "bHONEY", // ERC20 symbol
            _contractAddresses,
            params
        );
    }

    /// @dev Set parameters here!
    function deployFeesMarkets(BerpsDeployer deployer) internal {
        address _manager = msg.sender;
        int64 _maxNegativePnlOnOpenP = 40e10; // 40% max negative open PnL on 1 trade

        deployer.deployFeesMarkets(_manager, _maxNegativePnlOnOpenP);
    }

    /// @dev Set parameters here!
    function deployReferrals(BerpsDeployer deployer) internal {
        uint256 _startReferrerFeeP = 50;
        uint256 _openFeeP = 25;
        uint256 _targetVolumeHoney = 10_000e18; // (1e18)

        deployer.deployReferrals(_startReferrerFeeP, _openFeeP, _targetVolumeHoney);
    }

    /// @dev Set parameters here!
    /// @dev Ensure Pyth is set here! For mock, use address(0).
    function deployEntrypoint(BerpsDeployer deployer) internal {
        address _pyth = address(0);
        uint64 _staleTolerance = 30 seconds; // half of Pyth's `validTimePeriod`
        uint256 _maxPosHoney = 100_000e18; // max collat used for 1 trade (1e18) -> $100k

        deployer.deployEntrypoint(_pyth, _staleTolerance, _maxPosHoney);
    }

    /// @dev Set parameters here!
    function deploySettlement(BerpsDeployer deployer, address _honey) internal {
        uint64 _canExecuteTimeout = 6; // ~18-24 seconds timeout for executability
        uint256 _updateSlFeeP = 25; // 25% of open fee charged for updating SL
        uint256 _liqFeeP = 5; // 5% of position size goes to liquidator on liquidations

        deployer.deploySettlement(_honey, _canExecuteTimeout, _updateSlFeeP, _liqFeeP);
    }

    /// @dev Set parameters here!
    function deployOrders(BerpsDeployer deployer, address _honey) internal {
        address _gov = msg.sender;

        deployer.deployOrders(_honey, _gov);
    }

    /// @dev Set parameters here!
    /// @dev Ensure FeeCollector is set here!
    function deployVaultSafetyModule(BerpsDeployer deployer, address _honey) internal {
        address _manager = msg.sender;
        address _feeCollector = address(0);

        deployer.deployVaultSafetyModule(_manager, _honey, _feeCollector);
    }
}
