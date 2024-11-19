// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// chosen to use an initializer instead of a constructor
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// chosen not to use Solady because EIP-2612 is not needed
import {
    ERC20Upgradeable,
    IERC20,
    IERC20Metadata
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20VotesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";
import { Multicallable } from "solady/src/utils/Multicallable.sol";

import { Utils } from "../libraries/Utils.sol";
import { IBGT } from "./interfaces/IBGT.sol";
import { IBeaconDeposit } from "./interfaces/IBeaconDeposit.sol";
import { BGTStaker } from "./BGTStaker.sol";

/// @title Bera Governance Token
/// @author Berachain Team
/// @dev Should be owned by the governance module.
/// @dev Only allows minting BGT by the BlockRewardController contract.
/// @dev It's not upgradable even though it inherits from `ERC20VotesUpgradeable` and `OwnableUpgradeable`.
/// @dev This contract inherits from `Multicallable` to allow for batch calls for `activateBoost` by a third party.
contract BGT is IBGT, ERC20VotesUpgradeable, OwnableUpgradeable, Multicallable {
    using Utils for bytes4;

    string private constant NAME = "Bera Governance Token";
    string private constant SYMBOL = "BGT";

    /// @dev The length of the history buffer.
    uint32 private constant HISTORY_BUFFER_LENGTH = 8191;

    /// @dev Represents 100%. Chosen to be less granular.
    uint256 private constant ONE_HUNDRED_PERCENT = 1e4;

    /// @dev Represents 10%.
    uint256 private constant TEN_PERCENT = 1e3;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The address of the BlockRewardController contract.
    address internal _blockRewardController;

    /// @notice The BeaconDeposit contract that we are getting the operators for validators from.
    IBeaconDeposit public beaconDepositContract;

    /// @notice The BGTStaker contract that we are using to stake and withdraw BGT.
    /// @dev This contract is used to distribute dapp fees to BGT delegators.
    BGTStaker public staker;

    /// @notice The block delay for activating boosts.
    uint32 public activateBoostDelay;

    /// @notice The block delay for dropping boosts.
    uint32 public dropBoostDelay;

    /// @notice The struct of queued boosts
    /// @param blockNumberLast The last block number boost balance was queued
    /// @param balance The queued BGT balance to boost with
    struct QueuedBoost {
        uint32 blockNumberLast;
        uint128 balance;
    }

    /// @notice The struct of queued drop boosts
    /// @param blockNumberLast The last block number boost balance was queued for dropping
    /// @param balance The boosted BGT balance to drop boost with
    struct QueuedDropBoost {
        uint32 blockNumberLast;
        uint128 balance;
    }

    /// @notice The struct of user boosts
    /// @param boost The boost balance being used by the user
    /// @param queuedBoost The queued boost balance to be used by the user
    struct UserBoost {
        uint128 boost;
        uint128 queuedBoost;
    }

    /// @notice The struct of validator's queued commissions
    /// @param blockNumberLast The last block number commission rate was queued
    /// @param rate The commission rate for the validator
    struct QueuedCommission {
        uint32 blockNumberLast;
        uint224 rate;
    }

    /// @notice Total amount of BGT used for validator boosts
    uint128 public totalBoosts;

    /// @notice The mapping of queued boosts on a validator by an account
    mapping(address account => mapping(bytes pubkey => QueuedBoost)) public boostedQueue;

    /// @notice The mapping of queued drop boosts on a validator by an account
    mapping(address account => mapping(bytes pubkey => QueuedDropBoost)) public dropBoostQueue;

    /// @notice The mapping of balances used to boost validator rewards by an account
    mapping(address account => mapping(bytes pubkey => uint128)) public boosted;

    /// @notice The mapping of boost balances used by an account
    mapping(address account => UserBoost) internal userBoosts;

    /// @notice The mapping of boost balances for a validator
    mapping(bytes pubkey => uint128) public boostees;

    /// @notice The mapping of validator queued commission rates charged on new block rewards
    mapping(bytes pubkey => QueuedCommission) public queuedCommissions;

    /// @notice The mapping of validator commission rates charged on new block rewards.
    mapping(bytes pubkey => uint224 rate) public commissions;

    /// @notice The mapping of approved senders.
    mapping(address sender => bool) public isWhitelistedSender;

    /// @notice Initializes the BGT contract.
    /// @dev Should be called only once by the deployer in the same transaction.
    /// @dev Used instead of a constructor to make the `CREATE2` address independent of constructor arguments.
    function initialize(address owner) external initializer {
        __Ownable_init(owner);
        __ERC20_init(NAME, SYMBOL);
        // set the delay to the history buffer length
        activateBoostDelay = HISTORY_BUFFER_LENGTH;
        dropBoostDelay = HISTORY_BUFFER_LENGTH;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ACCESS CONTROL                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Throws if called by any account other than BlockRewardController.
    modifier onlyBlockRewardController() {
        if (msg.sender != _blockRewardController) NotBlockRewardController.selector.revertWith();
        _;
    }

    /// @dev Throws if the caller is not an approved sender.
    modifier onlyApprovedSender(address sender) {
        if (!isWhitelistedSender[sender]) NotApprovedSender.selector.revertWith();
        _;
    }

    /// @dev Throws if sender available unboosted balance less than amount
    modifier checkUnboostedBalance(address sender, uint256 amount) {
        _checkUnboostedBalance(sender, amount);
        _;
    }

    /// @notice check the invariant of the contract after the write operation
    modifier invariantCheck() {
        /// Run the method.
        _;

        /// Ensure that the contract is in a valid state after the write operation.
        _invariantCheck();
    }

    /// @dev Throws if the caller is not the operator of the validator.
    modifier onlyOperator(bytes calldata pubkey) {
        _onlyOperator(pubkey);
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBGT
    function whitelistSender(address sender, bool approved) external onlyOwner {
        isWhitelistedSender[sender] = approved;
        emit SenderWhitelisted(sender, approved);
    }

    /// @inheritdoc IBGT
    function setMinter(address _minter) external onlyOwner {
        if (_minter == address(0)) ZeroAddress.selector.revertWith();
        emit MinterChanged(_blockRewardController, _minter);
        _blockRewardController = _minter;
    }

    /// @inheritdoc IBGT
    function mint(address distributor, uint256 amount) external onlyBlockRewardController invariantCheck {
        super._mint(distributor, amount);
    }

    /// @inheritdoc IBGT
    function setBeaconDepositContract(address _beaconDepositContract) external onlyOwner {
        if (_beaconDepositContract == address(0)) ZeroAddress.selector.revertWith();
        emit BeaconDepositContractChanged(address(beaconDepositContract), _beaconDepositContract);
        beaconDepositContract = IBeaconDeposit(_beaconDepositContract);
    }

    /// @inheritdoc IBGT
    function setStaker(address _staker) external onlyOwner {
        if (_staker == address(0)) ZeroAddress.selector.revertWith();
        emit StakerChanged(address(staker), _staker);
        staker = BGTStaker(_staker);
    }

    /// @inheritdoc IBGT
    function setActivateBoostDelay(uint32 _activateBoostDelay) external onlyOwner {
        if (_activateBoostDelay == 0 || _activateBoostDelay > HISTORY_BUFFER_LENGTH) {
            InvalidActivateBoostDelay.selector.revertWith();
        }
        activateBoostDelay = _activateBoostDelay;
        emit ActivateBoostDelayChanged(_activateBoostDelay);
    }

    /// @inheritdoc IBGT
    function setDropBoostDelay(uint32 _dropBoostDelay) external onlyOwner {
        if (_dropBoostDelay == 0 || _dropBoostDelay > HISTORY_BUFFER_LENGTH) {
            InvalidDropBoostDelay.selector.revertWith();
        }
        dropBoostDelay = _dropBoostDelay;
        emit DropBoostDelayChanged(_dropBoostDelay);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    VALIDATOR BOOSTS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBGT
    function queueBoost(bytes calldata pubkey, uint128 amount) external checkUnboostedBalance(msg.sender, amount) {
        userBoosts[msg.sender].queuedBoost += amount;
        unchecked {
            QueuedBoost storage qb = boostedQueue[msg.sender][pubkey];
            // `userBoosts[msg.sender].queuedBoost` >= `qb.balance`
            // if the former doesn't overflow, the latter won't
            uint128 balance = qb.balance + amount;
            (qb.balance, qb.blockNumberLast) = (balance, uint32(block.number));
        }
        emit QueueBoost(msg.sender, pubkey, amount);
    }

    /// @inheritdoc IBGT
    function cancelBoost(bytes calldata pubkey, uint128 amount) external {
        QueuedBoost storage qb = boostedQueue[msg.sender][pubkey];
        qb.balance -= amount;
        unchecked {
            // `userBoosts[msg.sender].queuedBoost` >= `qb.balance`
            // if the latter doesn't underflow, the former won't
            userBoosts[msg.sender].queuedBoost -= amount;
        }
        emit CancelBoost(msg.sender, pubkey, amount);
    }

    /// @inheritdoc IBGT
    function activateBoost(address user, bytes calldata pubkey) external {
        QueuedBoost storage qb = boostedQueue[user][pubkey];
        (uint32 blockNumberLast, uint128 amount) = (qb.blockNumberLast, qb.balance);
        // `amount` zero will revert as it will fail with stake amount being zero at `stake` call.
        _checkEnoughTimePassed(blockNumberLast, activateBoostDelay);

        totalBoosts += amount;
        unchecked {
            // `totalBoosts` >= `boostees[validator]` >= `boosted[user][validator]`
            boostees[pubkey] += amount;
            boosted[user][pubkey] += amount;
            UserBoost storage userBoost = userBoosts[user];
            (uint128 boost, uint128 _queuedBoost) = (userBoost.boost, userBoost.queuedBoost);
            // `totalBoosts` >= `userBoosts[user].boost`
            // `userBoosts[user].queuedBoost` >= `boostedQueue[user][validator].balance`
            (userBoost.boost, userBoost.queuedBoost) = (boost + amount, _queuedBoost - amount);
        }
        delete boostedQueue[user][pubkey];

        staker.stake(user, amount);

        emit ActivateBoost(msg.sender, user, pubkey, amount);
    }

    ///` @inheritdoc IBGT
    function queueDropBoost(bytes calldata pubkey, uint128 amount) external {
        QueuedDropBoost storage qdb = dropBoostQueue[msg.sender][pubkey];
        uint128 dropBalance = qdb.balance + amount;
        // check if the user has enough boosted balance to drop
        if (boosted[msg.sender][pubkey] < dropBalance) NotEnoughBoostedBalance.selector.revertWith();
        (qdb.balance, qdb.blockNumberLast) = (dropBalance, uint32(block.number));
        emit QueueDropBoost(msg.sender, pubkey, dropBalance);
    }

    /// @inheritdoc IBGT
    function cancelDropBoost(bytes calldata pubkey, uint128 amount) external {
        QueuedDropBoost storage qdb = dropBoostQueue[msg.sender][pubkey];
        qdb.balance -= amount;
        emit CancelDropBoost(msg.sender, pubkey, amount);
    }

    /// @inheritdoc IBGT
    function dropBoost(address user, bytes calldata pubkey) external {
        QueuedDropBoost storage qdb = dropBoostQueue[user][pubkey];
        (uint32 blockNumberLast, uint128 amount) = (qdb.blockNumberLast, qdb.balance);
        _checkEnoughTimePassed(blockNumberLast, dropBoostDelay);
        // `amount` should be greater than zero to avoid reverting as
        // `withdraw` will fail with zero amount.
        unchecked {
            // queue drop boost gaurentees that the user has enough boosted balance to drop
            boosted[user][pubkey] -= amount;
            // `totalBoosts` >= `userBoosts[user].boost` >= `boosted[user][validator]`
            totalBoosts -= amount;
            userBoosts[user].boost -= amount;
            // boostees[validator]` >= `boosted[user][validator]`
            boostees[pubkey] -= amount;
        }
        delete dropBoostQueue[user][pubkey];
        staker.withdraw(user, amount);

        emit DropBoost(user, pubkey, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  VALIDATOR COMMISSIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBGT
    function queueCommissionChange(bytes calldata pubkey, uint256 rate) external onlyOperator(pubkey) {
        if (rate > TEN_PERCENT) InvalidCommission.selector.revertWith();

        QueuedCommission storage c = queuedCommissions[pubkey];
        (c.blockNumberLast, c.rate) = (uint32(block.number), uint224(rate));
        emit QueueCommissionChange(pubkey, commissions[pubkey], rate);
    }

    /// @inheritdoc IBGT
    function cancelCommissionChange(bytes calldata pubkey) external onlyOperator(pubkey) {
        delete queuedCommissions[pubkey];
        emit CancelCommissionChange(pubkey);
    }

    /// @inheritdoc IBGT
    function activateCommissionChange(bytes calldata pubkey) external {
        QueuedCommission storage c = queuedCommissions[pubkey];
        (uint32 blockNumberLast, uint224 rate) = (c.blockNumberLast, c.rate);
        // check if the commission is queued, if not revert with error
        if (blockNumberLast == 0) CommissionNotQueued.selector.revertWith();
        _checkEnoughTimePassed(blockNumberLast, HISTORY_BUFFER_LENGTH);

        commissions[pubkey] = rate;
        delete queuedCommissions[pubkey];
        emit ActivateCommissionChange(pubkey, rate);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ERC20 FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC20
    /// @dev Only allows approve if the caller is an approved sender.
    function approve(
        address spender,
        uint256 amount
    )
        public
        override(IERC20, ERC20Upgradeable)
        onlyApprovedSender(msg.sender)
        returns (bool)
    {
        return super.approve(spender, amount);
    }

    /// @inheritdoc IERC20
    /// @dev Only allows transfer if the caller is an approved sender and has enough unboosted balance.
    function transfer(
        address to,
        uint256 amount
    )
        public
        override(IERC20, ERC20Upgradeable)
        onlyApprovedSender(msg.sender)
        checkUnboostedBalance(msg.sender, amount)
        returns (bool)
    {
        return super.transfer(to, amount);
    }

    /// @inheritdoc IERC20
    /// @dev Only allows transferFrom if the from address is an approved sender and has enough unboosted balance.
    /// @dev It spends the allowance of the caller.
    function transferFrom(
        address from,
        address to,
        uint256 amount
    )
        public
        override(IERC20, ERC20Upgradeable)
        onlyApprovedSender(from)
        checkUnboostedBalance(from, amount)
        returns (bool)
    {
        return super.transferFrom(from, to, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          WRITES                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBGT
    function redeem(
        address receiver,
        uint256 amount
    )
        external
        invariantCheck
        checkUnboostedBalance(msg.sender, amount)
    {
        /// Burn the BGT token from the msg.sender account and reduce the total supply.
        super._burn(msg.sender, amount);
        /// Transfer the Native token to the receiver.
        SafeTransferLib.safeTransferETH(receiver, amount);
        emit Redeem(msg.sender, receiver, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBGT
    function minter() external view returns (address) {
        return _blockRewardController;
    }

    /// @inheritdoc IBGT
    function normalizedBoost(bytes calldata pubkey) external view returns (uint256) {
        if (totalBoosts == 0) return 0;
        return FixedPointMathLib.divWad(boostees[pubkey], totalBoosts);
    }

    /// @inheritdoc IBGT
    function boosts(address account) external view returns (uint128) {
        return userBoosts[account].boost;
    }

    /// @inheritdoc IBGT
    function queuedBoost(address account) external view returns (uint128) {
        return userBoosts[account].queuedBoost;
    }

    /// @inheritdoc IBGT
    function commissionRewardRate(bytes calldata pubkey, uint256 rewardRate) external view returns (uint256) {
        return FixedPointMathLib.fullMulDiv(rewardRate, commissions[pubkey], ONE_HUNDRED_PERCENT);
    }

    /// @inheritdoc IERC20Metadata
    function name() public pure override(IERC20Metadata, ERC20Upgradeable) returns (string memory) {
        return NAME;
    }

    /// @inheritdoc IERC20Metadata
    function symbol() public pure override(IERC20Metadata, ERC20Upgradeable) returns (string memory) {
        return SYMBOL;
    }

    //. @inheritdoc IBGT
    function unboostedBalanceOf(address account) public view returns (uint256) {
        UserBoost storage userBoost = userBoosts[account];
        (uint128 boost, uint128 _queuedBoost) = (userBoost.boost, userBoost.queuedBoost);
        return balanceOf(account) - boost - _queuedBoost;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          INTERNAL                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _checkUnboostedBalance(address sender, uint256 amount) private view {
        if (unboostedBalanceOf(sender) < amount) NotEnoughBalance.selector.revertWith();
    }

    function _checkEnoughTimePassed(uint32 blockNumberLast, uint32 blockBufferDelay) private view {
        unchecked {
            uint32 delta = uint32(block.number) - blockNumberLast;
            if (delta <= blockBufferDelay) NotEnoughTime.selector.revertWith();
        }
    }

    function _invariantCheck() private view {
        if (address(this).balance < totalSupply()) InvariantCheckFailed.selector.revertWith();
    }

    function _onlyOperator(bytes calldata pubkey) private view {
        if (msg.sender != beaconDepositContract.getOperator(pubkey)) NotOperator.selector.revertWith();
    }
}
