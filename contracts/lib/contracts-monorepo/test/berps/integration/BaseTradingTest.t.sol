// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { LibClone } from "solady/src/utils/LibClone.sol";

import "@pythnetwork/MockPyth.sol";

import "@mock/token/MockERC20.sol";
import "@mock/berps/MockFeeCollector.sol";

import { IReferrals } from "src/berps/interfaces/v0/IReferrals.sol";
import { IEntrypoint, Entrypoint } from "src/berps/core/v0/Entrypoint.sol";
import { FeesAccrued, IFeesAccrued } from "src/berps/core/v0/FeesAccrued.sol";
import { FeesMarkets, IFeesMarkets } from "src/berps/core/v0/FeesMarkets.sol";
import { Markets, IMarkets } from "src/berps/core/v0/Markets.sol";
import { Orders, IOrders } from "src/berps/core/v0/Orders.sol";
import { Settlement, ISettlement } from "src/berps/core/v0/Settlement.sol";
import { Vault, IVault } from "src/berps/core/v0/Vault.sol";
import { VaultSafetyModule } from "src/berps/core/v0/VaultSafetyModule.sol";

abstract contract BaseTradingTest is Test {
    MockERC20 honey;
    Orders orders;
    Entrypoint entrypoint;
    FeesMarkets feesMarkets;
    FeesAccrued feesAccrued;
    MockPyth mockOracle;
    VaultSafetyModule safetyModule;
    address bot = address(0x2222);
    address ref = address(0x3333);
    bytes32 mockPriceFeed = bytes32(0xeaa020c61cc479712813461ce153894a96a6c00b21ed0cfc2798d1f9a9e9c94a);

    function setUp() public virtual {
        honey = new MockERC20();
        honey.initialize("honey", "honey");
        honey.mint(bot, 1e40);

        {
            entrypoint = Entrypoint(payable(LibClone.deployERC1967(address(new Entrypoint()))));
            orders = Orders(LibClone.deployERC1967(address(new Orders())));
            safetyModule = VaultSafetyModule(LibClone.deployERC1967(address(new VaultSafetyModule())));
        }

        Settlement settlement;
        Vault bHoney;
        Markets markets;

        {
            settlement = Settlement(LibClone.deployERC1967(address(new Settlement())));
            feesAccrued = FeesAccrued(LibClone.deployERC1967(address(new FeesAccrued())));
            feesMarkets = FeesMarkets(LibClone.deployERC1967(address(new FeesMarkets())));
            markets = Markets(LibClone.deployERC1967(address(new Markets())));
            bHoney = Vault(LibClone.deployERC1967(address(new Vault())));
        }

        safetyModule.initialize(bot, address(honey), address(bHoney), address(new MockFeeCollector(address(honey))));
        IVault.ContractAddresses memory vaultAddresses = IVault.ContractAddresses({
            asset: address(honey),
            owner: bot,
            manager: bot,
            pnlHandler: address(settlement),
            safetyModule: address(safetyModule)
        });
        IVault.Params memory params = IVault.Params({
            _maxDailyAccPnlDelta: 1e18,
            _withdrawLockThresholdsPLow: 10_000_000_000_000_000_000,
            _withdrawLockThresholdsPHigh: 20_000_000_000_000_000_000,
            _maxSupplyIncreaseDailyP: 2e18,
            _epochLength: 3 minutes,
            _minRecollatP: 150e18,
            _safeMinSharePrice: 1.2e18
        });
        bHoney.initialize("bHoney", "bHoney", vaultAddresses, params);

        orders.initialize(
            address(honey), bot, address(markets), address(bHoney), address(entrypoint), address(settlement), ref
        );
        markets.initialize(address(orders));
        settlement.initialize(
            address(orders),
            address(feesMarkets),
            address(ref),
            address(feesAccrued),
            address(bHoney),
            address(honey),
            2,
            25,
            5
        );
        feesAccrued.initialize(address(orders), address(feesMarkets));
        feesMarkets.initialize(address(orders), bot, 40e10);

        vm.startPrank(bot, bot);
        honey.approve(address(bHoney), 1e40);
        bHoney.deposit(1e30, bot);
        IMarkets.Group memory group =
            IMarkets.Group({ name: "crypto", minLeverage: 2, maxLeverage: 100, maxCollateralP: 10 });
        markets.addGroup(group);
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = mockPriceFeed;
        ids[1] = mockPriceFeed;
        IMarkets.Feed memory feed = IMarkets.Feed({
            ids: ids,
            feedCalculation: IMarkets.FeedCalculation.SINGULAR,
            useConfSpread: false,
            confThresholdP: 0.25 * 1e10,
            useEma: false
        });
        IMarkets.Pair memory pair = IMarkets.Pair({ from: "pair", to: "pair", feed: feed, groupIndex: 0, feeIndex: 0 });
        IMarkets.Fee memory fee = IMarkets.Fee({
            name: "pair",
            openFeeP: 1e9, // 0.1%
            closeFeeP: 1e9, // 0.1%
            limitOrderFeeP: 5e8, // 0.05%
            minLevPosHoney: 10e18 // 10 HONEY
         });
        markets.addFee(fee);
        markets.addPair(pair);
        IFeesAccrued.PairParams memory pp = IFeesAccrued.PairParams({ groupIndex: 0, baseBorrowAPR: 10 * 1e10 });
        feesAccrued.setPairParams(0, pp);
        orders.setMaxOpenInterestHoney(0, 1e30);
        vm.stopPrank();

        // disable referrals in this test
        vm.mockCall(ref, abi.encodeWithSelector(IReferrals.getTraderReferrer.selector), abi.encode(address(0)));
    }

    function initializeTrading(uint256 singleUpdateFee) public virtual {
        mockOracle = new MockPyth(1 days, singleUpdateFee);
        entrypoint.initialize(
            address(mockOracle), address(orders), address(feesMarkets), address(feesAccrued), 1 days, 100_000e18
        );
    }
}
