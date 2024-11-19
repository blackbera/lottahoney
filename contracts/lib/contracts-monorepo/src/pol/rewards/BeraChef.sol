// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Utils } from "../../libraries/Utils.sol";
import { IBeaconDeposit } from "../interfaces/IBeaconDeposit.sol";
import { IBeraChef } from "../interfaces/IBeraChef.sol";
import { BerachainRewardsVault } from "./BerachainRewardsVault.sol";
import { IBerachainRewardsVaultFactory } from "../interfaces/IBerachainRewardsVaultFactory.sol";

/// @title BeraChef
/// @author Berachain Team
/// @notice The BeraChef contract is responsible for managing the cutting boards, operators of
/// the validators and the friends of the chef.
/// @dev It should be owned by the governance module.
contract BeraChef is IBeraChef, OwnableUpgradeable, UUPSUpgradeable {
    using Utils for bytes4;

    /// @dev Represents 100%. Chosen to be less granular.
    uint96 internal constant ONE_HUNDRED_PERCENT = 1e4;
    uint64 public constant MAX_CUTTING_BOARD_BLOCK_DELAY = 1_315_000; // with 2 second block time, this is ~30 days.

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The address of the distributor contract.
    address public distributor;
    /// @notice The addred of the reward vault factory contract.
    address public factory;

    IBeaconDeposit public beaconDepositContract;

    /// @notice The delay in blocks before a new cutting board can go into effect.
    uint64 public cuttingBoardBlockDelay;

    /// @dev The maximum number of weights per cutting board.
    uint8 public maxNumWeightsPerCuttingBoard;

    /// @dev Mapping of validator coinbase address to active cutting board.
    mapping(bytes valPubkey => CuttingBoard) internal activeCuttingBoards;

    /// @dev Mapping of validator coinbase address to queued cutting board.
    mapping(bytes valPubkey => CuttingBoard) internal queuedCuttingBoards;

    /// @notice Mapping of receiver address to whether they are white-listed as a friend of the chef.
    mapping(address receiver => bool) public isFriendOfTheChef;

    /// @notice The Default cutting board is used when a validator does not have a cutting board.
    CuttingBoard internal defaultCuttingBoard;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _distributor,
        address _factory,
        address _governance,
        address _beaconDepositContract,
        uint8 _maxNumWeightsPerCuttingBoard
    )
        external
        initializer
    {
        __Ownable_init(_governance);
        // slither-disable-next-line missing-zero-check
        distributor = _distributor;
        // slither-disable-next-line missing-zero-check
        factory = _factory;
        // slither-disable-next-line missing-zero-check
        beaconDepositContract = IBeaconDeposit(_beaconDepositContract);
        if (_maxNumWeightsPerCuttingBoard == 0) {
            MaxNumWeightsPerCuttingBoardIsZero.selector.revertWith();
        }
        emit MaxNumWeightsPerCuttingBoardSet(_maxNumWeightsPerCuttingBoard);
        maxNumWeightsPerCuttingBoard = _maxNumWeightsPerCuttingBoard;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyDistributor() {
        if (msg.sender != distributor) {
            NotDistributor.selector.revertWith();
        }
        _;
    }

    modifier onlyOperator(bytes calldata valPubkey) {
        if (msg.sender != beaconDepositContract.getOperator(valPubkey)) {
            NotOperator.selector.revertWith();
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBeraChef
    function setMaxNumWeightsPerCuttingBoard(uint8 _maxNumWeightsPerCuttingBoard) external onlyOwner {
        if (_maxNumWeightsPerCuttingBoard == 0) {
            MaxNumWeightsPerCuttingBoardIsZero.selector.revertWith();
        }
        maxNumWeightsPerCuttingBoard = _maxNumWeightsPerCuttingBoard;
        emit MaxNumWeightsPerCuttingBoardSet(_maxNumWeightsPerCuttingBoard);
    }

    /// @inheritdoc IBeraChef
    function setCuttingBoardBlockDelay(uint64 _cuttingBoardBlockDelay) external onlyOwner {
        if (_cuttingBoardBlockDelay > MAX_CUTTING_BOARD_BLOCK_DELAY) {
            CuttingBoardBlockDelayTooLarge.selector.revertWith();
        }
        cuttingBoardBlockDelay = _cuttingBoardBlockDelay;
        emit CuttingBoardBlockDelaySet(_cuttingBoardBlockDelay);
    }

    /// @inheritdoc IBeraChef
    function updateFriendsOfTheChef(address receiver, bool isFriend) external onlyOwner {
        isFriendOfTheChef[receiver] = isFriend;
        if (!isFriend) {
            // If the receiver is no longer a friend of the chef, check if the default cutting board is still valid.
            if (!_checkIfStillValid(defaultCuttingBoard.weights)) {
                InvalidCuttingBoardWeights.selector.revertWith();
            }
        } else {
            // Check if the proposed friend is registered in the factory
            address stakeToken = address(BerachainRewardsVault(receiver).stakeToken());
            address factoryVault = IBerachainRewardsVaultFactory(factory).getVault(stakeToken);
            if (receiver != factoryVault) {
                NotFactoryVault.selector.revertWith();
            }
        }
        emit FriendsOfTheChefUpdated(receiver, isFriend);
    }

    /// @inheritdoc IBeraChef
    function setDefaultCuttingBoard(CuttingBoard calldata cb) external onlyOwner {
        // validate if the weights are valid.
        _validateWeights(cb.weights);

        emit SetDefaultCuttingBoard(cb);
        defaultCuttingBoard = cb;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          SETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBeraChef
    function queueNewCuttingBoard(
        bytes calldata valPubkey,
        uint64 startBlock,
        Weight[] calldata weights
    )
        external
        onlyOperator(valPubkey)
    {
        // adds a delay before a new cutting board can go into effect
        if (startBlock <= block.number + cuttingBoardBlockDelay) {
            InvalidStartBlock.selector.revertWith();
        }

        // validate if the weights are valid.
        _validateWeights(weights);

        // delete the existing queued cutting board
        CuttingBoard storage qcb = queuedCuttingBoards[valPubkey];
        delete qcb.weights;

        // queue the new cutting board
        qcb.startBlock = startBlock;
        Weight[] storage storageWeights = qcb.weights;
        for (uint256 i; i < weights.length;) {
            storageWeights.push(weights[i]);
            unchecked {
                ++i;
            }
        }
        emit QueueCuttingBoard(valPubkey, startBlock, weights);
    }

    /// @inheritdoc IBeraChef
    function activateReadyQueuedCuttingBoard(bytes calldata valPubkey, uint256 blockNumber) external onlyDistributor {
        if (!isQueuedCuttingBoardReady(valPubkey, blockNumber)) return;
        CuttingBoard storage qcb = queuedCuttingBoards[valPubkey];
        uint64 startBlock = qcb.startBlock;
        activeCuttingBoards[valPubkey] = qcb;
        emit ActivateCuttingBoard(valPubkey, startBlock, qcb.weights);
        // delete the queued cutting board
        delete queuedCuttingBoards[valPubkey];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBeraChef
    /// @dev Returns the active cutting board if validator has a cutting board and the weights are still valid,
    /// otherwise the default cutting board.
    function getActiveCuttingBoard(bytes calldata valPubkey) external view returns (CuttingBoard memory) {
        CuttingBoard memory acb = activeCuttingBoards[valPubkey];

        // check if the weights are still valid.
        if (acb.startBlock > 0 && _checkIfStillValid(acb.weights)) {
            return acb;
        }

        // If we reach here, either the weights are not valid or validator does not have any cutting board, return the
        // default cutting board.
        // @dev The validator or its operator need to update their cutting board to a valid one for them to direct
        // the block rewards.
        return defaultCuttingBoard;
    }

    /// @inheritdoc IBeraChef
    function getQueuedCuttingBoard(bytes calldata valPubkey) external view returns (CuttingBoard memory) {
        return queuedCuttingBoards[valPubkey];
    }

    /// @inheritdoc IBeraChef
    function getSetActiveCuttingBoard(bytes calldata valPubkey) external view returns (CuttingBoard memory) {
        return activeCuttingBoards[valPubkey];
    }

    /// @inheritdoc IBeraChef
    function getDefaultCuttingBoard() external view returns (CuttingBoard memory) {
        return defaultCuttingBoard;
    }

    /// @inheritdoc IBeraChef
    function isQueuedCuttingBoardReady(bytes calldata valPubkey, uint256 blockNumber) public view returns (bool) {
        uint64 startBlock = queuedCuttingBoards[valPubkey].startBlock;
        return startBlock != 0 && startBlock <= blockNumber;
    }

    /// @inheritdoc IBeraChef
    function isReady() external view returns (bool) {
        // return that the default cutting board is set.
        return defaultCuttingBoard.weights.length > 0;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         INTERNAL                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Validates the weights of a cutting board.
     * @param weights The weights of the cutting board.
     */
    function _validateWeights(Weight[] calldata weights) internal view {
        if (weights.length > maxNumWeightsPerCuttingBoard) {
            TooManyWeights.selector.revertWith();
        }

        // ensure that the total weight is 100%.
        uint96 totalWeight;
        for (uint256 i; i < weights.length;) {
            Weight calldata weight = weights[i];
            // ensure that all receivers are approved for every weight in the cutting board.
            if (!isFriendOfTheChef[weight.receiver]) {
                NotFriendOfTheChef.selector.revertWith();
            }
            totalWeight += weight.percentageNumerator;
            unchecked {
                ++i;
            }
        }
        if (totalWeight != ONE_HUNDRED_PERCENT) {
            InvalidCuttingBoardWeights.selector.revertWith();
        }
    }

    /**
     * @notice Checks if the weights of a cutting board are still valid.
     * @notice This method is used to check if the weights of a cutting board are still valid in flight.
     * @param weights The weights of the cutting board.
     * @return True if the weights are still valid, otherwise false.
     */
    function _checkIfStillValid(Weight[] memory weights) internal view returns (bool) {
        uint256 length = weights.length;
        for (uint256 i; i < length;) {
            // At the first occurrence of a receiver that is not a friend of the chef, return false.
            if (!isFriendOfTheChef[weights[i].receiver]) {
                return false;
            }
            unchecked {
                ++i;
            }
        }

        // If all receivers are friends of the chef, return true.
        return true;
    }
}
