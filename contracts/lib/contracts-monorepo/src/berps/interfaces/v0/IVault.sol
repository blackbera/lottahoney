// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IVault {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         INITIALIZE                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev prevents stack too deep error
    struct ContractAddresses {
        address asset;
        address owner;
        address manager; // access to emergency functions
        address pnlHandler;
        address safetyModule;
    }

    /// @dev prevents stack too deep error
    struct Params {
        uint256 _maxDailyAccPnlDelta;
        uint256 _withdrawLockThresholdsPLow;
        uint256 _withdrawLockThresholdsPHigh;
        uint256 _maxSupplyIncreaseDailyP;
        uint256 _epochLength;
        uint256 _minRecollatP;
        uint256 _safeMinSharePrice;
    }

    /// @notice Only callable via a ERC1967 Proxy contract.
    function initialize(
        string memory _name,
        string memory _symbol,
        ContractAddresses calldata _contractAddresses,
        Params calldata params
    )
        external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event AddressParamUpdated(string name, address newValue);
    event NumberParamUpdated(string name, uint256 newValue);
    event WithdrawLockThresholdsPUpdated(uint256[2] newValue);
    event CurrentMaxSupplyUpdated(uint256 newValue);
    event DailyAccPnlDeltaReset();
    event ShareToAssetsPriceUpdated(uint256 newValue);
    event OpenTradesPnlFeedCallFailed();
    event NewEpoch(uint256 indexed newEpoch, uint256 newEpochPositiveOpenPnl);
    event NewEpochForced(uint256 indexed newEpoch);

    event WithdrawalRequested(address indexed owner, uint256 indexed unlockEpoch, uint256 newSharesAmount);
    event WithdrawalCanceled(address indexed owner, uint256 indexed unlockEpoch, uint256 newSharesAmount);

    event FeesDistributed(uint256 assetsToVault, uint256 totalDepositedSnapshot);
    event FeesSentToSafetyModule(uint256 assets, uint256 shareToAssetsPriceSnapshot);
    event AssetsSent(address indexed sender, address indexed receiver, uint256 assets);
    event AssetsReceived(address indexed sender, address indexed user, uint256 assets);
    event AssetsDirectedToSafetyModule(address indexed sender, uint256 assets, uint256 collatPSnapshot);
    event AccTimeWeightedMarketCapStored(uint256 currentTime, uint256 newAccValue);
    event Recapitalized(address indexed sender, uint256 assetsRecapitalized, uint256 collatPSnapshot);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            VIEWS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function manager() external view returns (address);

    function epochLength() external view returns (uint256);

    function currentEpoch() external view returns (uint256);

    function currentEpochStart() external view returns (uint256);

    function currentEpochPositiveOpenPnl() external view returns (uint256);

    function availableAssets() external view returns (uint256);

    function tvl() external view returns (uint256);

    function totalDeposited() external view returns (uint256);

    function collateralizationP() external view returns (uint256);

    function marketCap() external view returns (uint256);

    function getPendingAccTimeWeightedMarketCap(uint256 currentTime) external view returns (uint256);

    function completeBalanceOf(address owner) external view returns (uint256);

    function completeBalanceOfAssets(address owner) external view returns (uint256);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       PnL OPERATIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function sendAssets(uint256 assets, address receiver) external;

    function receiveAssets(uint256 assets, address user) external;

    function distributeReward(uint256 assets) external;

    function recapitalize(uint256 assets) external;
}
