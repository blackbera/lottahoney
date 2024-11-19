// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { ERC20Upgradeable, IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { Utils } from "../../../libraries/Utils.sol";
import { BerpsErrors } from "../../utils/BerpsErrors.sol";

import { IVault } from "../../interfaces/v0/IVault.sol";

/// @notice Vault serves as the Honey vault for trading liquidity.
contract Vault is ERC20Upgradeable, ERC4626Upgradeable, OwnableUpgradeable, UUPSUpgradeable, IVault {
    using Math for uint256;
    using Utils for bytes4;
    using SafeTransferLib for address;

    // Contracts & Addresses (adjustable)
    address public manager; // access to emergency functions
    address public pnlHandler;
    address public safetyModule;

    // Parameters (constant)
    uint256 constant PRECISION = 1e18; // 18 decimals (acc values & price)
    uint256 constant PRECISION_2 = 1e40; // 40 decimals (acc block weighted  market cap)
    uint256 constant MIN_DAILY_ACC_PNL_DELTA = PRECISION / 10; // 0.1 (price delta)
    uint256 constant MAX_SUPPLY_INCREASE_DAILY_P = 50 * PRECISION; // 50% / day (when under collat)
    uint256 constant MAX_EPOCH_LENGTH = 3 weeks; // max epoch length
    uint256 constant MAX_PERCENT = 100 * PRECISION; // 100% (PRECISION of 1e18)

    // Parameters (adjustable)
    uint256 public maxDailyAccPnlDelta; // PRECISION (max daily price delta from closed pnl)
    uint256[2] public withdrawLockThresholdsP; // PRECISION (% of over collat, used with numEpochsWithdrawLocked)
    uint256[3] public numEpochsWithdrawLocked; // number of epochs locked for withdraws
    uint256 public maxSupplyIncreaseDailyP; // PRECISION (% per day, when under collat)
    uint256 public minRecollatP; // PRECISION (% collat required to recapitalize)

    // Price state
    uint256 public shareToAssetsPrice; // PRECISION (x honey / 1 bhoney)
    uint256 public safeMinSharePrice; // PRECISION
    int256 public accPnlPerToken; // PRECISION (updated in real-time)
    uint256 public accRewardsPerToken; // PRECISION

    // Closed Pnl state
    int256 public dailyAccPnlDelta; // PRECISION
    uint256 public lastDailyAccPnlDeltaReset; // timestamp

    // Epochs state (withdrawals)
    uint256 public epochLength; // time in seconds
    uint256 public currentEpoch; // global id
    uint256 public currentEpochStart; // timestamp
    uint256 public currentEpochPositiveOpenPnl; // 1e18

    // Deposit / Withdraw state
    uint256 public currentMaxSupply; // 1e18
    uint256 public lastMaxSupplyUpdate; // timestamp
    mapping(address => mapping(uint256 => uint256)) public withdrawRequests; // owner => unlock epoch => shares

    // Statistics (not used for contract logic)
    uint256 public totalDeposited; // 1e18 (assets)
    int256 public totalClosedPnl; // 1e18 (assets)
    uint256 public totalRewards; // 1e18 (assets)
    int256 public totalLiability; // 1e18 (assets)
    uint256 public totalRecapitalized; // 1e18 (assets)

    // Useful acc values
    uint256 public accTimeWeightedMarketCap; // 1e40, acc sum of (time elapsed / market cap)
    uint256 public accTimeWeightedMarketCapLastStored; // timestamp

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /// @inheritdoc IVault
    function initialize(
        string memory _name,
        string memory _symbol,
        IVault.ContractAddresses calldata _contractAddresses,
        IVault.Params calldata params
    )
        external
        initializer
    {
        if (
            _contractAddresses.asset == address(0) || _contractAddresses.owner == address(0)
                || _contractAddresses.manager == address(0) || _contractAddresses.pnlHandler == address(0)
                || _contractAddresses.safetyModule == address(0) || params._maxDailyAccPnlDelta < MIN_DAILY_ACC_PNL_DELTA
                || params._withdrawLockThresholdsPHigh <= params._withdrawLockThresholdsPLow
                || params._maxSupplyIncreaseDailyP > MAX_SUPPLY_INCREASE_DAILY_P || params._epochLength > MAX_EPOCH_LENGTH
                || params._minRecollatP < MAX_PERCENT || params._safeMinSharePrice < PRECISION
        ) {
            BerpsErrors.WrongParams.selector.revertWith();
        }

        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20(_contractAddresses.asset));
        _transferOwnership(_contractAddresses.owner);

        manager = _contractAddresses.manager;
        pnlHandler = _contractAddresses.pnlHandler;
        safetyModule = _contractAddresses.safetyModule;

        maxDailyAccPnlDelta = params._maxDailyAccPnlDelta;
        withdrawLockThresholdsP[0] = params._withdrawLockThresholdsPLow;
        withdrawLockThresholdsP[1] = params._withdrawLockThresholdsPHigh;
        maxSupplyIncreaseDailyP = params._maxSupplyIncreaseDailyP;
        minRecollatP = params._minRecollatP;

        shareToAssetsPrice = PRECISION;
        safeMinSharePrice = params._safeMinSharePrice;
        epochLength = params._epochLength;
        currentEpoch = 1;
        currentEpochStart = block.timestamp;

        // Locked epochs will always be 3, 2, or 1 depending on collateralization ratio.
        numEpochsWithdrawLocked = [3, 2, 1];
    }

    // Modifiers
    modifier onlyManager() {
        if (_msgSender() != manager) BerpsErrors.Unauthorized.selector.revertWith();
        _;
    }

    modifier checks(uint256 assetsOrShares) {
        if (shareToAssetsPrice == 0) BerpsErrors.PriceZero.selector.revertWith();
        if (assetsOrShares == 0) BerpsErrors.WrongParams.selector.revertWith();
        _;
    }

    // Manage addresses
    function transferOwnership(address newOwner) public override onlyOwner {
        if (newOwner == address(0)) BerpsErrors.WrongParams.selector.revertWith();
        _transferOwnership(newOwner);
    }

    function updateManager(address newValue) external onlyOwner {
        if (newValue == address(0)) BerpsErrors.WrongParams.selector.revertWith();
        manager = newValue;
        emit AddressParamUpdated("manager", newValue);
    }

    function updatePnlHandler(address newValue) external onlyOwner {
        if (newValue == address(0)) BerpsErrors.WrongParams.selector.revertWith();
        pnlHandler = newValue;
        emit AddressParamUpdated("pnlHandler", newValue);
    }

    function updateSafetyModule(address newValue) external onlyOwner {
        if (newValue == address(0)) BerpsErrors.WrongParams.selector.revertWith();
        safetyModule = newValue;
        emit AddressParamUpdated("safetyModule", newValue);
    }

    function updateMaxDailyAccPnlDelta(uint256 newValue) external onlyManager {
        if (newValue < MIN_DAILY_ACC_PNL_DELTA) BerpsErrors.WrongParams.selector.revertWith();
        maxDailyAccPnlDelta = newValue;
        emit NumberParamUpdated("maxDailyAccPnlDelta", newValue);
    }

    function updateWithdrawLockThresholdsP(uint256[2] memory newValue) external onlyManager {
        if (newValue[1] <= newValue[0]) BerpsErrors.WrongParams.selector.revertWith();
        withdrawLockThresholdsP = newValue;
        emit WithdrawLockThresholdsPUpdated(newValue);
    }

    function updateMaxSupplyIncreaseDailyP(uint256 newValue) external onlyManager {
        if (newValue > MAX_SUPPLY_INCREASE_DAILY_P) BerpsErrors.WrongParams.selector.revertWith();
        maxSupplyIncreaseDailyP = newValue;
        emit NumberParamUpdated("maxSupplyIncreaseDailyP", newValue);
    }

    function updateEpochLength(uint256 newValue) external onlyManager {
        if (newValue > MAX_EPOCH_LENGTH) BerpsErrors.WrongParams.selector.revertWith();
        epochLength = newValue;
        emit NumberParamUpdated("epochLength", newValue);
    }

    function updateMinRecollatP(uint256 newValue) external onlyManager {
        if (newValue < MAX_PERCENT) BerpsErrors.WrongParams.selector.revertWith();
        minRecollatP = newValue;
        emit NumberParamUpdated("minRecollatP", newValue);
    }

    function updateSafeMinSharePrice(uint256 newValue) external onlyManager {
        if (newValue < PRECISION) BerpsErrors.WrongParams.selector.revertWith();
        safeMinSharePrice = newValue;
        emit NumberParamUpdated("safeMinSharePrice", newValue);
    }

    // View helper functions
    function maxAccPnlPerToken() public view returns (uint256) {
        // Represents how many fees we've collected (the supposed max positive pnl we can support).
        return PRECISION + accRewardsPerToken;
    }

    function collateralizationP() public view returns (uint256) {
        // PRECISION (%)
        uint256 _maxAccPnlPerToken = maxAccPnlPerToken();
        return (
            (
                accPnlPerToken > 0
                    ? (_maxAccPnlPerToken - uint256(accPnlPerToken))
                    : (_maxAccPnlPerToken + uint256(accPnlPerToken * (-1)))
            ) * MAX_PERCENT
        ) / _maxAccPnlPerToken;
    }

    function withdrawEpochsTimelock() public view returns (uint256) {
        uint256 collatP = collateralizationP();
        uint256 overCollatP = (collatP - FixedPointMathLib.min(collatP, MAX_PERCENT));

        return overCollatP > withdrawLockThresholdsP[1]
            ? numEpochsWithdrawLocked[2]
            : (overCollatP > withdrawLockThresholdsP[0] ? numEpochsWithdrawLocked[1] : numEpochsWithdrawLocked[0]);
    }

    function totalSharesBeingWithdrawn(address owner) public view returns (uint256 shares) {
        for (uint256 i = currentEpoch; i <= currentEpoch + numEpochsWithdrawLocked[0]; i++) {
            shares += withdrawRequests[owner][i];
        }
    }

    function getPendingAccTimeWeightedMarketCap(uint256 currentTime) public view returns (uint256) {
        return accTimeWeightedMarketCap
            + ((currentTime - accTimeWeightedMarketCapLastStored) * PRECISION_2) / FixedPointMathLib.max(marketCap(), 1);
    }

    // Public helper functions
    function tryUpdateCurrentMaxSupply() public {
        if (block.timestamp - lastMaxSupplyUpdate >= 1 days) {
            currentMaxSupply = (totalSupply() * (PRECISION * 100 + maxSupplyIncreaseDailyP)) / (PRECISION * 100);
            lastMaxSupplyUpdate = block.timestamp;

            emit CurrentMaxSupplyUpdated(currentMaxSupply);
        }
    }

    function tryResetDailyAccPnlDelta() public {
        if (block.timestamp - lastDailyAccPnlDeltaReset >= 1 days) {
            dailyAccPnlDelta = 0;
            lastDailyAccPnlDeltaReset = block.timestamp;

            emit DailyAccPnlDeltaReset();
        }
    }

    function storeAccTimeWeightedMarketCap() public {
        accTimeWeightedMarketCap = getPendingAccTimeWeightedMarketCap(block.timestamp);
        accTimeWeightedMarketCapLastStored = block.timestamp;

        emit AccTimeWeightedMarketCapStored(block.timestamp, accTimeWeightedMarketCap);
    }

    // Private helper functions
    function updateShareToAssetsPrice() private {
        storeAccTimeWeightedMarketCap();

        // If under-collateralized (pnl < 0), the share price incorporates how much we are under-collateralized by.
        // Otherwise (pnl > 0), the share price only represents how many fees we have collected.
        shareToAssetsPrice = maxAccPnlPerToken() - (accPnlPerToken > 0 ? uint256(accPnlPerToken) : uint256(0)); // PRECISION

        emit ShareToAssetsPriceUpdated(shareToAssetsPrice);
    }

    /// @notice Returns the full balance of `owner`, including any shares being withdrawn.
    function completeBalanceOf(address owner) external view returns (uint256) {
        return super.balanceOf(owner);
    }

    /// @notice Returns the `assets` amount of the full balance of `owner`, including any shares being withdrawn.
    function completeBalanceOfAssets(address owner) external view returns (uint256) {
        return _convertToAssets(super.balanceOf(owner), Math.Rounding.Floor);
    }

    // Override ERC-20 functions (prevent sending from address that is withdrawing)
    function balanceOf(address account) public view override(ERC20Upgradeable, IERC20) returns (uint256) {
        return super.balanceOf(account) - totalSharesBeingWithdrawn(account);
    }

    function transfer(address to, uint256 amount) public override(ERC20Upgradeable, IERC20) returns (bool) {
        address sender = _msgSender();
        if (amount > balanceOf(sender)) BerpsErrors.PendingWithdrawal.selector.revertWith();

        _transfer(sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    )
        public
        override(ERC20Upgradeable, IERC20)
        returns (bool)
    {
        if (amount > balanceOf(from)) BerpsErrors.PendingWithdrawal.selector.revertWith();
        _spendAllowance(from, _msgSender(), amount);

        _transfer(from, to, amount);
        return true;
    }

    // Override ERC-4626 view functions
    function decimals() public view override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
        return ERC4626Upgradeable.decimals();
    }

    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    )
        internal
        view
        override
        returns (uint256 shares)
    {
        return assets.mulDiv(PRECISION, shareToAssetsPrice, rounding);
    }

    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    )
        internal
        view
        override
        returns (uint256 assets)
    {
        // Prevent overflow when called from maxDeposit with maxMint = uint.max
        if (shares == type(uint256).max && shareToAssetsPrice >= PRECISION) {
            return shares;
        }
        return shares.mulDiv(shareToAssetsPrice, PRECISION, rounding);
    }

    function maxMint(address) public view override returns (uint256) {
        return accPnlPerToken > 0
            ? currentMaxSupply - FixedPointMathLib.min(currentMaxSupply, totalSupply())
            : type(uint256).max;
    }

    function maxDeposit(address owner) public view override returns (uint256) {
        return _convertToAssets(maxMint(owner), Math.Rounding.Floor);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return FixedPointMathLib.min(withdrawRequests[owner][currentEpoch], totalSupply() - 1);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return _convertToAssets(maxRedeem(owner), Math.Rounding.Floor);
    }

    // Override ERC-4626 interactions (call scaleVariables on every deposit /
    // withdrawal)
    function deposit(uint256 assets, address receiver) public override checks(assets) returns (uint256) {
        if (assets > maxDeposit(receiver)) BerpsErrors.MaxDeposit.selector.revertWith();
        uint256 shares = previewDeposit(assets);
        scaleVariables(shares, assets, true);

        _deposit(_msgSender(), receiver, assets, shares);
        return shares;
    }

    function mint(uint256 shares, address receiver) public override checks(shares) returns (uint256) {
        if (shares > maxMint(receiver)) BerpsErrors.MaxDeposit.selector.revertWith();
        uint256 assets = previewMint(shares);
        scaleVariables(shares, assets, true);

        _deposit(_msgSender(), receiver, assets, shares);
        return assets;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        override
        checks(assets)
        returns (uint256)
    {
        if (assets > maxWithdraw(owner)) BerpsErrors.MaxWithdraw.selector.revertWith();
        uint256 shares = previewWithdraw(assets);

        // Update withdraw request for this epoch to reflect the withdrawal amount.
        withdrawRequests[owner][currentEpoch] -= shares;
        emit WithdrawalCanceled(owner, currentEpoch, withdrawRequests[owner][currentEpoch]);

        scaleVariables(shares, assets, false);

        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        override
        checks(shares)
        returns (uint256)
    {
        if (shares > maxRedeem(owner)) BerpsErrors.MaxWithdraw.selector.revertWith();
        withdrawRequests[owner][currentEpoch] -= shares;
        uint256 assets = previewRedeem(shares);
        scaleVariables(shares, assets, false);

        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return assets;
    }

    // called before any deposit/withdraw of honey assets
    function scaleVariables(uint256 shares, uint256 assets, bool isDeposit) private {
        uint256 supply = totalSupply();

        if (accPnlPerToken < 0) {
            accPnlPerToken =
                (accPnlPerToken * int256(supply)) / (isDeposit ? int256(supply + shares) : int256(supply - shares));
        } else if (accPnlPerToken > 0) {
            totalLiability +=
                ((int256(shares) * totalLiability) / int256(supply)) * (isDeposit ? int256(1) : int256(-1));
        }

        totalDeposited = isDeposit ? totalDeposited + assets : totalDeposited - assets;

        storeAccTimeWeightedMarketCap();
    }

    // Withdraw requests (need to be done before calling 'withdraw' / 'redeem')
    function makeWithdrawRequest(uint256 shares) external {
        address owner = _msgSender();
        if (shares > balanceOf(owner)) BerpsErrors.InsufficientBalance.selector.revertWith();

        uint256 unlockEpoch = currentEpoch + withdrawEpochsTimelock();
        uint256 newSharesAmount = withdrawRequests[owner][unlockEpoch] + shares;
        withdrawRequests[owner][unlockEpoch] = newSharesAmount;

        emit WithdrawalRequested(owner, unlockEpoch, newSharesAmount);
    }

    function cancelWithdrawRequest(uint256 shares, uint256 unlockEpoch) external {
        address owner = _msgSender();
        if (shares > withdrawRequests[owner][unlockEpoch]) BerpsErrors.InsufficientBalance.selector.revertWith();
        withdrawRequests[owner][unlockEpoch] -= shares;

        emit WithdrawalCanceled(owner, unlockEpoch, withdrawRequests[owner][unlockEpoch]);
    }

    /// @notice Distributes a reward (trading fees) to either:
    /// 1. the vault safety module if the vault is over the safe minimum share to assets price
    /// 2. OR evenly to all stakers of the vault otherwise.
    /// @dev Caller must have approved the vault to transfer the assets!
    function distributeReward(uint256 assets) external {
        address sender = _msgSender();

        // Check to see if we can send these assets to the vault safety module.
        if (shareToAssetsPrice >= safeMinSharePrice) {
            asset().safeTransferFrom(sender, safetyModule, assets);

            emit FeesSentToSafetyModule(assets, shareToAssetsPrice);
            return;
        }

        // Otherwise distribute these assets to all stakers.
        asset().safeTransferFrom(sender, address(this), assets);

        uint256 supply = totalSupply();
        if (supply > 0) {
            accRewardsPerToken += (assets * PRECISION) / supply;
        }
        updateShareToAssetsPrice();
        totalRewards += assets;
        totalDeposited += assets;

        emit FeesDistributed(assets, totalDeposited);
    }

    // PnL interactions (happens often, so also used to trigger other actions)
    function sendAssets(uint256 assets, address receiver) external {
        address sender = _msgSender();
        if (sender != pnlHandler) BerpsErrors.Unauthorized.selector.revertWith();

        int256 accPnlDelta = 0;
        uint256 supply = totalSupply();
        if (supply > 0) {
            accPnlDelta = int256(assets.mulDiv(PRECISION, supply, Math.Rounding.Ceil));
        }

        accPnlPerToken += accPnlDelta;
        if (accPnlPerToken > int256(maxAccPnlPerToken())) BerpsErrors.NotEnoughAssets.selector.revertWith();

        tryResetDailyAccPnlDelta();
        dailyAccPnlDelta += accPnlDelta;
        if (dailyAccPnlDelta > int256(maxDailyAccPnlDelta)) BerpsErrors.MaxDailyPnL.selector.revertWith();

        totalLiability += int256(assets);
        totalClosedPnl += int256(assets);
        currentEpochPositiveOpenPnl += assets;

        newEpochRequest();
        tryUpdateCurrentMaxSupply();

        asset().safeTransfer(receiver, assets);

        emit AssetsSent(sender, receiver, assets);
    }

    /// @notice Receives assets for increasing collateralization. It will go to either:
    ///  1. the vault safety module if we are collateralized over the max of recaptalization threshold
    ///  2. OR the vault's collateralization otherwise.
    /// @dev Caller must have approved the vault to transfer the assets!
    function receiveAssets(uint256 assets, address user) external {
        address sender = _msgSender();

        // Check if we are overcollateralized enough to send these assets to the safety module.
        uint256 _collatP = collateralizationP();
        if (_collatP > minRecollatP) {
            asset().safeTransferFrom(sender, safetyModule, assets);

            emit AssetsDirectedToSafetyModule(sender, assets, _collatP);
            return;
        }

        // If not, we will receive these assets to increase our collateralization.
        asset().safeTransferFrom(sender, address(this), assets);

        int256 accPnlDelta = 0;
        uint256 supply = totalSupply();
        if (supply > 0) {
            accPnlDelta = int256((assets * PRECISION) / supply);
        }
        accPnlPerToken -= accPnlDelta;

        tryResetDailyAccPnlDelta();
        dailyAccPnlDelta -= accPnlDelta;

        totalLiability -= int256(assets);
        totalClosedPnl -= int256(assets);

        newEpochRequest();
        tryUpdateCurrentMaxSupply();

        emit AssetsReceived(sender, user, assets);
    }

    /// @dev Caller must have approved the vault to transfer the assets!
    function recapitalize(uint256 assets) external {
        // Check that the current collateralization ratio under the min recollateralization threshold.
        uint256 _collatP = collateralizationP();
        if (_collatP > minRecollatP) {
            BerpsErrors.WrongCollatPForRecapital.selector.revertWith(_collatP);
        }

        // Ensure that we aren't recapitalizing with too many assets.
        uint256 supply = totalSupply();
        if (assets > (uint256(accPnlPerToken) * supply) / PRECISION) BerpsErrors.AboveMax.selector.revertWith();

        // Transfer the assets to the vault.
        address sender = _msgSender();
        asset().safeTransferFrom(sender, address(this), assets);

        // Update the pnl accounting math.
        int256 accPnlDelta = int256((assets * PRECISION) / supply);
        accPnlPerToken -= accPnlDelta;
        updateShareToAssetsPrice();
        totalRecapitalized += assets;

        emit Recapitalized(sender, assets, collateralizationP());
    }

    function newEpochRequest() private {
        if (block.timestamp - currentEpochStart > epochLength) {
            startNewEpoch();
        }
    }

    function forceNewEpoch() external {
        if (block.timestamp - currentEpochStart <= epochLength) BerpsErrors.TooEarly.selector.revertWith();
        startNewEpoch();
        emit NewEpochForced(currentEpoch);
    }

    // Increment epoch and update feed value
    function startNewEpoch() private {
        updateShareToAssetsPrice();

        currentEpoch++;
        tryUpdateCurrentMaxSupply();

        emit NewEpoch(currentEpoch, currentEpochPositiveOpenPnl);

        currentEpochStart = block.timestamp;
        currentEpochPositiveOpenPnl = 0;
    }

    function tvl() public view returns (uint256) {
        return (maxAccPnlPerToken() * totalSupply()) / PRECISION; // 1e18
    }

    function availableAssets() public view returns (uint256) {
        return (uint256(int256(maxAccPnlPerToken()) - accPnlPerToken) * totalSupply()) / PRECISION; // 1e18
    }

    function marketCap() public view returns (uint256) {
        return (totalSupply() * shareToAssetsPrice) / PRECISION; // 1e18
    }
}
