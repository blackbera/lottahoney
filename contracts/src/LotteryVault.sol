// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IEntropy } from "@pythnetwork/entropy-sdk-solidity/IEntropy.sol";
import { IEntropyConsumer } from "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import { IBerachainRewardsVault } from "contracts-monorepo/pol/interfaces/IBerachainRewardsVault.sol";
import { PrzHoney } from "./PrzHoney.sol";
import { console } from "forge-std/console.sol";

/**
 * @title LotteryVault
 * @dev A lottery system using Pyth's Entropy for randomness and Berachain's reward system
 * @author przhi.eth
 * @notice This contract manages a lottery system where users can buy tickets with HONEY
 * @custom:security-contact security@przhi.eth
 */
contract LotteryVault is IEntropyConsumer, Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user purchases lottery tickets
    /// @param buyer Address of the ticket buyer
    /// @param ticketId ID of the lottery
    /// @param amount Number of tickets purchased
    event TicketPurchased(address indexed buyer, uint256 ticketId, uint256 amount);

    /// @notice Emitted when a lottery winner is selected
    /// @param winner Address of the winner
    /// @param amount Prize amount won
    event LotteryWinner(address indexed winner, uint256 amount);

    /// @notice Emitted when incentives are added to the rewards vault
    /// @param amount Amount of incentives added
    event IncentiveAdded(uint256 amount);

    /// @notice Emitted when a lottery draw is initiated
    /// @param lotteryId ID of the lottery being drawn
    event DrawInitiated(uint256 lotteryId);

    /// @notice Emitted when a new lottery starts
    /// @param lotteryId ID of the new lottery
    /// @param ticketPrice Price per ticket
    /// @param endTime Timestamp when lottery ends
    event LotteryStarted(uint256 lotteryId, uint256 ticketPrice, uint256 endTime);

    /// @notice Emitted when a winner claims their reward
    /// @param winner Address of the winner claiming
    /// @param amount Amount claimed
    event RewardClaimed(address indexed winner, uint256 amount);

    /// @notice Emitted when receipt tokens are burned
    /// @param user Address whose tokens were burned
    /// @param amount Amount of tokens burned
    event ReceiptTokensBurned(address indexed user, uint256 amount);

    /// @notice Emitted when a withdrawal fails
    /// @param participant Address of the failed withdrawal
    /// @param amount Amount that failed to withdraw
    event WithdrawalFailed(address indexed participant, uint256 amount);

    /// @notice Emitted when PrzHoney token address is set
    /// @param przHoney Address of the PrzHoney token
    event PrzHoneySet(address przHoney);

    /// @notice Emitted when a lottery is stopped
    /// @param lotteryId ID of the stopped lottery
    event LotteryStopped(uint256 indexed lotteryId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an invalid amount is provided
    error InvalidAmount();
    /// @notice Thrown when trying to draw before lottery ends
    error LotteryNotEnded();
    /// @notice Thrown when lottery has already ended
    error LotteryEnded();
    /// @notice Thrown when there are no participants
    error NoParticipants();
    /// @notice Thrown when a draw is already in progress
    error DrawInProgress();
    /// @notice Thrown when no lottery is active
    error NoActiveLottery();
    /// @notice Thrown when trying to start an already active lottery
    error LotteryAlreadyActive();
    /// @notice Thrown when an invalid ticket price is set
    error InvalidTicketPrice();
    /// @notice Thrown when an invalid duration is set
    error InvalidDuration();
    /// @notice Thrown when non-winner tries to claim
    error NotWinner();
    /// @notice Thrown when gas reserves are too low
    error InsufficientGasReserves();
    /// @notice Thrown when staking is not allowed
    error StakingNotAllowed();
    /// @notice Thrown when VRF request is already pending
    error VRFRequestAlreadyPending();
    /// @notice Thrown when round ID is invalid
    /// @param roundId The invalid round ID
    error VRFInvalidRoundId(uint256 roundId);
    /// @notice Thrown when request data is invalid
    error VRFInvalidRequestData();
    /// @notice Thrown when randomness is invalid
    error VRFInvalidRandomness();
    /// @notice Thrown when participant count is invalid
    error VRFInvalidParticipantCount();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Purchase fee percentage (1%)
    uint256 private constant PURCHASE_FEE = 100;

    /// @notice Winner fee percentage (3%)
    uint256 private constant WINNER_FEE = 300;

    /// @notice Fee denominator for percentage calculations
    uint256 private constant FEE_DENOMINATOR = 10000;

    /// @notice Minimum ETH to keep for gas fees
    uint256 private constant MIN_GAS_RESERVE = 1 ether;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Token used for purchasing tickets (HONEY)
    IERC20 public paymentToken;

    /// @notice Receipt token for tracking participation (przHONEY)
    PrzHoney public receiptToken;

    /// @notice Berachain rewards vault for staking
    IBerachainRewardsVault public rewardVault;

    /// @notice Pyth entropy service for randomness
    IEntropy public entropy;

    /// @notice Pyth entropy provider address
    address public provider;

    /// @notice Current lottery end timestamp
    uint256 public lotteryEndTime;

    /// @notice Current lottery ID
    uint256 public currentLotteryId;

    /// @notice Price per ticket in HONEY
    uint256 public ticketPrice;

    /// @notice Total pool amount for current lottery
    uint256 public totalPool;

    /// @notice Whether a draw is currently in progress
    bool public drawInProgress;

    /// @notice Whether a lottery is currently active
    bool public lotteryActive;

    /// @notice Accumulated fees from purchases and winners
    uint256 public accumulatedFees;

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of lottery ID to participant addresses
    mapping(uint256 => address[]) public lotteryParticipants;

    /// @notice Mapping of user address to ticket count
    mapping(address => uint256) public userTicketCount;

    /// @notice Mapping of lottery ID to winner address
    mapping(uint256 => address) public lotteryWinners;

    /// @notice Mapping of lottery ID to prize amount
    mapping(uint256 => uint256) public lotteryPrizes;

    /// @notice Mapping of lottery ID to prize claimed status
    mapping(uint256 => bool) public prizesClaimed;

    /// @notice Mapping of sequence number to lottery ID for Pyth callbacks
    mapping(uint64 => uint256) public sequenceNumberToLotteryId;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the lottery vault
     * @param _paymentToken Address of the HONEY token
     * @param _owner Address of the contract owner
     * @param _rewardVault Address of the Berachain rewards vault
     * @param _entropy Address of the Pyth entropy service
     * @param _provider Address of the Pyth entropy provider
     */
    constructor(
        address _paymentToken,
        address _owner,
        address _rewardVault,
        address _entropy,
        address _provider
    ) Ownable(_owner) {
        paymentToken = IERC20(_paymentToken);
        rewardVault = IBerachainRewardsVault(_rewardVault);
        entropy = IEntropy(_entropy);
        provider = _provider;
        currentLotteryId = 1;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows contract to receive ETH
    receive() external payable {}

    /**
     * @notice Claims reward for a winning lottery ticket
     * @param lotteryId ID of the lottery to claim from
     */
    function claimReward(uint256 lotteryId) external {
        address winner = lotteryWinners[lotteryId];
        require(winner != address(0), "No winner for this lottery");
        require(!prizesClaimed[lotteryId], "Prize already claimed");
        
        uint256 prize = lotteryPrizes[lotteryId];
        require(prize > 0, "No prize available");

        prizesClaimed[lotteryId] = true;
        paymentToken.safeTransfer(winner, prize);

        uint256 winnerTickets = userTicketCount[winner];
        receiptToken.burn(winner, winnerTickets);

        emit RewardClaimed(winner, prize);
        emit ReceiptTokensBurned(winner, winnerTickets);

        _startNewLottery();
    }

    /**
     * @notice Purchases lottery tickets
     * @param amount Number of tickets to purchase
     */
    function purchaseTicket(uint256 amount) external {
        if (!lotteryActive) revert NoActiveLottery();
        if (block.timestamp >= lotteryEndTime) revert LotteryEnded();
        if (amount == 0) revert InvalidAmount();

        uint256 totalCost = amount * ticketPrice;
        uint256 purchaseFee = (totalCost * PURCHASE_FEE) / FEE_DENOMINATOR;
        
        paymentToken.safeTransferFrom(msg.sender, address(this), totalCost);
        totalPool += (totalCost - purchaseFee);
        accumulatedFees += purchaseFee;
        
        receiptToken.mint(address(this), amount);
        receiptToken.approve(address(rewardVault), amount);
        rewardVault.delegateStake(msg.sender, amount);
        
        lotteryParticipants[currentLotteryId].push(msg.sender);
        userTicketCount[msg.sender] += amount;

        emit TicketPurchased(msg.sender, currentLotteryId, amount);
    }

    /**
     * @notice Starts a new lottery round
     * @dev Anyone can call this, but only when no lottery is active
     */
    function startLottery() external {
        if (lotteryActive) revert LotteryAlreadyActive();

        ticketPrice = 1 ether;
        lotteryEndTime = block.timestamp + 10 minutes;
        lotteryActive = true;

        emit LotteryStarted(currentLotteryId, ticketPrice, lotteryEndTime);
    }

    /**
     * @notice Force starts a new lottery round, resetting all state
     * @dev Only callable by owner, used to unstick lottery in weird states
     */
    function forceNewLottery() external onlyOwner {
        totalPool = 0;
        currentLotteryId += 1;
        lotteryEndTime = block.timestamp + 10 minutes;
        drawInProgress = false;
        lotteryActive = true;

        emit LotteryStarted(currentLotteryId, ticketPrice, lotteryEndTime);
    }

    /**
     * @notice Stops the current lottery
     * @dev Only callable by owner, used to stop lottery in weird states
     */
    function stopLottery() external onlyOwner {
        lotteryActive = false;
        drawInProgress = false;
        totalPool = 0;
        lotteryEndTime = 0;
        
        emit LotteryStopped(currentLotteryId);
    }

    /**
     * @notice Initiates the lottery draw using Pyth entropy
     */
    function initiateDraw() external {
        if (!lotteryActive) revert NoActiveLottery();
        if (block.timestamp < lotteryEndTime) revert LotteryNotEnded();
        if (lotteryParticipants[currentLotteryId].length == 0) revert NoParticipants();
        if (drawInProgress) revert DrawInProgress();
        
        drawInProgress = true;
        
        bytes32 userRandomNumber = keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            msg.sender
        ));

        uint128 requestFee = entropy.getFee(provider);
        uint64 sequenceNumber = entropy.requestWithCallback{value: requestFee}(
            provider,
            userRandomNumber
        );

        sequenceNumberToLotteryId[sequenceNumber] = currentLotteryId;
        
        emit DrawInitiated(currentLotteryId);
    }

    /**
     * @notice Adds accumulated fees as incentives to the reward vault
     * @dev Only callable by owner
     * @param amount Amount of fees to add as incentives (0 for all)
     */
    function addAccumulatedFeesAsIncentives(uint256 amount) external onlyOwner {
        uint256 amountToAdd = amount == 0 ? accumulatedFees : amount;
        if (amountToAdd > accumulatedFees) revert InvalidAmount();
        if (amountToAdd == 0) revert InvalidAmount();

        accumulatedFees -= amountToAdd;
        paymentToken.approve(address(rewardVault), amountToAdd);
        rewardVault.addIncentive(address(paymentToken), amountToAdd, 1);

        emit IncentiveAdded(amountToAdd);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets current lottery participants
     * @return Array of participant addresses
     */
    function getCurrentParticipants() external view returns (address[] memory) {
        return lotteryParticipants[currentLotteryId];
    }

    /**
     * @notice Gets remaining time in current lottery
     * @return Time remaining in seconds
     */
    function getTimeRemaining() external view returns (uint256) {
        if (block.timestamp >= lotteryEndTime) return 0;
        return lotteryEndTime - block.timestamp;
    }

    /**
     * @notice Gets information about a specific lottery
     * @param lotteryId ID of the lottery
     * @return winner Address of the winner
     * @return prize Amount won
     * @return participants Array of participant addresses
     */
    function getLotteryInfo(uint256 lotteryId) external view returns (
        address winner,
        uint256 prize,
        address[] memory participants
    ) {
        winner = lotteryWinners[lotteryId];
        prize = lotteryPrizes[lotteryId];
        participants = lotteryParticipants[lotteryId];
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraws excess gas from contract
     * @dev Only callable by owner
     */
    function withdrawExcessGas() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > MIN_GAS_RESERVE, "No excess gas to withdraw");
        uint256 excess = balance - MIN_GAS_RESERVE;
        (bool success, ) = owner().call{value: excess}("");
        require(success, "Gas withdrawal failed");
    }

    /**
     * @notice Sets the PrzHoney token address
     * @dev Only callable by owner
     * @param _przHoney Address of the PrzHoney token
     */
    function setPrzHoney(address _przHoney) external onlyOwner {
        require(_przHoney != address(0), "Zero address not allowed");
        receiptToken = PrzHoney(_przHoney);
        PrzHoney(_przHoney).approve(address(rewardVault), type(uint256).max);
        emit PrzHoneySet(_przHoney);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Starts a new lottery round
     */
    function _startNewLottery() internal {
        totalPool = 0;
        currentLotteryId += 1;
        lotteryEndTime = block.timestamp + 1 days;
        drawInProgress = false;
        lotteryActive = true;
    }

    /**
     * @notice Callback function for Pyth entropy
     * @param sequenceNumber Sequence number of the request
     * @param randomNumber Random number provided by Pyth
     */
    function entropyCallback(
        uint64 sequenceNumber,
        address,
        bytes32 randomNumber
    ) internal override {
        uint256 lotteryId = sequenceNumberToLotteryId[sequenceNumber];
        uint256 participantCount = lotteryParticipants[lotteryId].length;
        if (participantCount == 0) revert VRFInvalidParticipantCount();
        
        uint256 winnerIndex = uint256(randomNumber) % participantCount;
        address winner = lotteryParticipants[lotteryId][winnerIndex];
        
        uint256 winnerFee = (totalPool * WINNER_FEE) / FEE_DENOMINATOR;
        uint256 winnerPrize = totalPool - winnerFee;

        // Handle participant withdrawals
        for (uint256 i = 0; i < participantCount; i++) {
            address participant = lotteryParticipants[lotteryId][i];
            uint256 participantStake = userTicketCount[participant];
            
            if (participantStake > 0) {
                try rewardVault.delegateWithdraw(participant, participantStake) {
                    receiptToken.burn(participant, participantStake);
                    userTicketCount[participant] = 0;
                    emit ReceiptTokensBurned(participant, participantStake);
                } catch {
                    emit WithdrawalFailed(participant, participantStake);
                }
            }
        }

        // Transfer prize to winner
        paymentToken.safeTransfer(winner, winnerPrize);

        // Add winner fee to accumulated fees instead of immediate incentive
        accumulatedFees += winnerFee;

        lotteryWinners[lotteryId] = winner;
        lotteryPrizes[lotteryId] = winnerPrize;

        emit LotteryWinner(winner, winnerPrize);
        // Remove the IncentiveAdded event since we're just accumulating fees

        // Reset lottery state
        totalPool = 0;
        currentLotteryId += 1;
        lotteryEndTime = 0;
        drawInProgress = false;
        lotteryActive = false;
    }

    /**
     * @notice Required by IEntropyConsumer
     * @return Address of the entropy service
     */
    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }
} 