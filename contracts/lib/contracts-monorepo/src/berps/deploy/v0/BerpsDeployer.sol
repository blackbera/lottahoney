// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { Ownable } from "solady/src/auth/Ownable.sol";

import { Create2Deployer } from "../../../base/Create2Deployer.sol";
import { Utils } from "../../../libraries/Utils.sol";
import { BerpsErrors } from "../../utils/BerpsErrors.sol";

// Contracts
import { FeesAccrued } from "../../core/v0/FeesAccrued.sol";
import { Vault, IVault } from "../../core/v0/Vault.sol";
import { VaultSafetyModule } from "../../core/v0/VaultSafetyModule.sol";
import { FeesMarkets } from "../../core/v0/FeesMarkets.sol";
import { Markets } from "../../core/v0/Markets.sol";
import { Referrals } from "../../core/v0/Referrals.sol";
import { Entrypoint, IEntrypoint } from "../../core/v0/Entrypoint.sol";
import { Settlement } from "../../core/v0/Settlement.sol";
import { Orders } from "../../core/v0/Orders.sol";

import { MockPyth } from "@pythnetwork/MockPyth.sol";

import { Implementations, Salts } from "./Structs.sol";

/// @title BerpsDeployer
/// @author Berachain Team
/// @notice The BerpsDeployer contract is responsible for atomically deploying and initializing the Berps contracts.
/// @dev The proxies of the Berps contracts are deployed at deterministic addresses.
contract BerpsDeployer is Create2Deployer, Ownable {
    using Utils for bytes4;

    /// @notice The CREATE2 salts for each of the 8 Berps contracts.
    /// @dev Should be left unmodified after first set.
    Salts public salts;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                STORAGE of CONTRACT ADDRESSES               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The Berps contracts implementations.
    /// @dev Should be left unmodified after first set.
    Implementations public impls;

    /// @notice The FeesAccrued proxy contract.
    FeesAccrued public feesAccruedProxy;

    /// @notice The Vault proxy contract.
    Vault public vaultProxy;

    /// @notice The FeesMarkets proxy contract.
    FeesMarkets public feesMarketsProxy;

    /// @notice The Markets proxy contract.
    Markets public marketsProxy;

    /// @notice The Referrals proxy contract.
    Referrals public referralsProxy;

    /// @notice The Entrypoint proxy contract.
    Entrypoint public entrypointProxy;

    /// @notice The Settlement proxy contract.
    Settlement public settlementProxy;

    /// @notice The Orders proxy contract.
    Orders public ordersProxy;

    /// @notice The VaultSafetyModule proxy contract.
    VaultSafetyModule public vaultSafetyModuleProxy;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Requires that all implementations are non-zero addresses.
    /// @dev Assumes that the implementation addresses are valid.
    constructor(Implementations memory _impls, Salts memory _salts) {
        if (
            _impls.feesAccrued == address(0) || _impls.vault == address(0) || _impls.feesMarkets == address(0)
                || _impls.markets == address(0) || _impls.referrals == address(0) || _impls.entrypoint == address(0)
                || _impls.settlement == address(0) || _impls.orders == address(0) || _impls.vaultSafetyModule == address(0)
        ) BerpsErrors.WrongParams.selector.revertWith();

        impls = _impls;
        salts = _salts;

        _initializeOwner(msg.sender);
    }

    function _guardInitializeOwner() internal pure override returns (bool guard) {
        return true;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   DEPLOYMENT of CONTRACTS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Atomically deploy and initialize the FeesAccrued proxy.
    /// @dev Will revert if called more than once due to trying to initialize the same proxy again.
    /// @dev Uses `ordersProxy` and `feesMarketsProxy` for the call to `initialize`.
    function deployFeesAccrued() external onlyOwner {
        // Deploy the FeesAccrued proxy with CREATE2.
        feesAccruedProxy = FeesAccrued(deployProxyWithCreate2(impls.feesAccrued, salts.feesAccrued));

        // Initialize the FeesAccrued proxy with the relevant addresses.
        feesAccruedProxy.initialize(getOrdersProxy(), getFeesMarketsProxy());
    }

    /// @notice Atomically deploy and initialize the Vault proxy.
    /// @dev Will revert if called more than once due to trying to initialize the same proxy again.
    /// @param _contractAddresses Overwrites fields `pnlHandler` to `settlementProxy` and `safetyModule` to
    /// `safetyModuleProxy` for the call to `initialize`.
    function deployVault(
        string memory _name,
        string memory _symbol,
        IVault.ContractAddresses memory _contractAddresses,
        IVault.Params memory params
    )
        external
        onlyOwner
    {
        // Deploy the Vault proxy with CREATE2.
        vaultProxy = Vault(deployProxyWithCreate2(impls.vault, salts.vault));

        // Initialize the Vault proxy with the relevant addresses.
        _contractAddresses.pnlHandler = getSettlementProxy();
        _contractAddresses.safetyModule = getVaultSafetyModuleProxy();
        vaultProxy.initialize(_name, _symbol, _contractAddresses, params);
    }

    /// @notice Atomically deploy and initialize the FeesMarkets proxy.
    /// @dev Will revert if called more than once due to trying to initialize the same proxy again.
    /// @dev Uses `ordersProxy` for the call to `initialize`.
    function deployFeesMarkets(address _manager, int64 _maxNegativePnlOnOpenP) external onlyOwner {
        // Deploy the FeesMarkets proxy with CREATE2.
        feesMarketsProxy = FeesMarkets(deployProxyWithCreate2(impls.feesMarkets, salts.feesMarkets));

        // Initialize the FeesMarkets proxy.
        feesMarketsProxy.initialize(getOrdersProxy(), _manager, _maxNegativePnlOnOpenP);
    }

    /// @notice Atomically deploy and initialize the Markets proxy.
    /// @dev Will revert if called more than once due to trying to initialize the same proxy again.
    /// @dev Uses `ordersProxy` for the call to `initialize`.
    function deployMarkets() external onlyOwner {
        // Deploy the Markets proxy with CREATE2.
        marketsProxy = Markets(deployProxyWithCreate2(impls.markets, salts.markets));

        // Initialize the Markets proxy.
        marketsProxy.initialize(getOrdersProxy());
    }

    /// @notice Atomically deploy and initialize the Referrals proxy.
    /// @dev Will revert if called more than once due to trying to initialize the same proxy again.
    /// @dev Uses `ordersProxy` for the call to `initialize`.
    function deployReferrals(
        uint256 _startReferrerFeeP,
        uint256 _openFeeP,
        uint256 _targetVolumeHoney
    )
        external
        onlyOwner
    {
        // Deploy the Referrals proxy with CREATE2.
        referralsProxy = Referrals(deployProxyWithCreate2(impls.referrals, salts.referrals));

        // Initialize the Referrals proxy.
        referralsProxy.initialize(getOrdersProxy(), _startReferrerFeeP, _openFeeP, _targetVolumeHoney);
    }

    /// @notice Atomically deploy and initialize the Entrypoint proxy.
    /// @dev Will revert if called more than once due to trying to initialize the same proxy again.
    /// @param _pyth Will deploy and use the MockPyth contract if given as `address(0)`.
    /// @dev Uses `feesAccruedProxy`, `feesMarketsProxy`, `settlementProxy`, `ordersProxy` for the call to
    /// `initialize`.
    function deployEntrypoint(address _pyth, uint64 _staleTolerance, uint256 _maxPosHoney) external onlyOwner {
        // Simulate real Pyth if the real Pyth contract is not provided.
        if (_pyth == address(0)) _pyth = address(new MockPyth(_staleTolerance, 1));

        // Deploy the Entrypoint proxy with CREATE2.
        entrypointProxy = Entrypoint(payable(deployProxyWithCreate2(impls.entrypoint, salts.entrypoint)));

        // Initialize the Entrypoint proxy.
        entrypointProxy.initialize(
            _pyth, getOrdersProxy(), getFeesMarketsProxy(), getFeesAccruedProxy(), _staleTolerance, _maxPosHoney
        );
    }

    /// @notice Atomically deploy and initialize the Settlement proxy.
    /// @dev Will revert if called more than once due to trying to initialize the same proxy again.
    /// @dev Uses `feesAccruedProxy`, `vaultProxy`, `feesMarketsProxy`, `referralsProxy`, `ordersProxy` for the call to
    /// `initialize`.
    function deploySettlement(
        address _honey,
        uint64 _canExecuteTimeout,
        uint256 _updateSlFeeP,
        uint256 _liqFeeP
    )
        external
        onlyOwner
    {
        // Deploy the Settlement proxy with CREATE2.
        settlementProxy = Settlement(deployProxyWithCreate2(impls.settlement, salts.settlement));

        // Initialize the Settlement proxy.
        settlementProxy.initialize(
            getOrdersProxy(),
            getFeesMarketsProxy(),
            getReferralsProxy(),
            getFeesAccruedProxy(),
            getVaultProxy(),
            _honey,
            _canExecuteTimeout,
            _updateSlFeeP,
            _liqFeeP
        );
    }

    /// @notice Atomically deploy and initialize the Orders proxy.
    /// @dev Will revert if called more than once due to trying to initialize the same proxy again.
    /// @dev Uses `vaultProxy`, `marketsProxy`, `referralsProxy`, `entrypointProxy`, `settlementProxy` for the call to
    /// `initialize`.
    function deployOrders(address _honey, address _gov) external onlyOwner {
        // Deploy the Orders proxy with CREATE2.
        ordersProxy = Orders(deployProxyWithCreate2(impls.orders, salts.orders));

        // Initialize the Orders proxy.
        ordersProxy.initialize(
            _honey,
            _gov,
            getMarketsProxy(),
            getVaultProxy(),
            getEntrypointProxy(),
            getSettlementProxy(),
            getReferralsProxy()
        );
    }

    /// @notice Atomically deploy and initialize the VaultSafetyModule proxy.
    /// @dev Will revert if called more than once due to trying to initialize the same proxy again.
    /// @dev Uses `vaultProxy` for the call to `initialize`.
    function deployVaultSafetyModule(address _manager, address _honey, address _feeCollector) external onlyOwner {
        // Deploy the VaultSafetyModule proxy with CREATE2.
        vaultSafetyModuleProxy =
            VaultSafetyModule(deployProxyWithCreate2(impls.vaultSafetyModule, salts.vaultSafetyModule));

        // Initialize the VaultSafetyModule proxy.
        vaultSafetyModuleProxy.initialize(_manager, _honey, getVaultProxy(), _feeCollector);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           HELPERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function getFeesAccruedProxy() internal view returns (address _feesAccruedProxy) {
        _feesAccruedProxy = address(feesAccruedProxy);
        if (_feesAccruedProxy == address(0)) {
            _feesAccruedProxy = getCreate2ProxyAddress(impls.feesAccrued, salts.feesAccrued);
        }
    }

    function getVaultProxy() internal view returns (address _vaultProxy) {
        _vaultProxy = address(vaultProxy);
        if (_vaultProxy == address(0)) {
            _vaultProxy = getCreate2ProxyAddress(impls.vault, salts.vault);
        }
    }

    function getFeesMarketsProxy() internal view returns (address _feesMarketsProxy) {
        _feesMarketsProxy = address(feesMarketsProxy);
        if (_feesMarketsProxy == address(0)) {
            _feesMarketsProxy = getCreate2ProxyAddress(impls.feesMarkets, salts.feesMarkets);
        }
    }

    function getMarketsProxy() internal view returns (address _marketsProxy) {
        _marketsProxy = address(marketsProxy);
        if (_marketsProxy == address(0)) {
            _marketsProxy = getCreate2ProxyAddress(impls.markets, salts.markets);
        }
    }

    function getReferralsProxy() internal view returns (address _referralsProxy) {
        _referralsProxy = address(referralsProxy);
        if (_referralsProxy == address(0)) {
            _referralsProxy = getCreate2ProxyAddress(impls.referrals, salts.referrals);
        }
    }

    function getEntrypointProxy() internal view returns (address _entrypointProxy) {
        _entrypointProxy = address(entrypointProxy);
        if (_entrypointProxy == address(0)) {
            _entrypointProxy = getCreate2ProxyAddress(impls.entrypoint, salts.entrypoint);
        }
    }

    function getSettlementProxy() internal view returns (address _settlementProxy) {
        _settlementProxy = address(settlementProxy);
        if (_settlementProxy == address(0)) {
            _settlementProxy = getCreate2ProxyAddress(impls.settlement, salts.settlement);
        }
    }

    function getOrdersProxy() internal view returns (address _ordersProxy) {
        _ordersProxy = address(ordersProxy);
        if (_ordersProxy == address(0)) {
            _ordersProxy = getCreate2ProxyAddress(impls.orders, salts.orders);
        }
    }

    function getVaultSafetyModuleProxy() internal view returns (address _vaultSafetyModuleProxy) {
        _vaultSafetyModuleProxy = address(vaultSafetyModuleProxy);
        if (_vaultSafetyModuleProxy == address(0)) {
            _vaultSafetyModuleProxy = getCreate2ProxyAddress(impls.vaultSafetyModule, salts.vaultSafetyModule);
        }
    }
}
