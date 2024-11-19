// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import { IPOLErrors } from "./IPOLErrors.sol";

/// @notice Interface of the BeraChef module
interface IBeraChef is IPOLErrors {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Represents a CuttingBoard entry
    struct CuttingBoard {
        // The block this cutting board goes into effect.
        uint64 startBlock;
        // The weights of the cutting board.
        Weight[] weights;
    }

    /// @notice Represents a Weight entry
    struct Weight {
        // The address of the receiver that this weight is for.
        address receiver;
        // The fraction of rewards going to this receiver.
        // the percentage denominator is: ONE_HUNDRED_PERCENT = 10000
        // the actual fraction is: percentageNumerator / ONE_HUNDRED_PERCENT
        // e.g. percentageNumerator for 50% is 5000, because 5000 / 10000 = 0.5
        uint96 percentageNumerator;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when the maximum number of weights per cutting board has been set.
    /// @param maxNumWeightsPerCuttingBoard The maximum number of weights per cutting board.
    event MaxNumWeightsPerCuttingBoardSet(uint8 maxNumWeightsPerCuttingBoard);

    /// @notice Emitted when the delay in blocks before a new cutting board can go into effect has been set.
    /// @param cuttingBoardBlockDelay The delay in blocks before a new cutting board can go into effect.
    event CuttingBoardBlockDelaySet(uint64 cuttingBoardBlockDelay);

    /// @notice Emitted when the friends of the chef have been updated.
    /// @param receiver The address to remove or add as a friend of the chef.
    /// @param isFriend The whitelist status; true if the receiver is being whitelisted, false otherwise.
    event FriendsOfTheChefUpdated(address indexed receiver, bool indexed isFriend);

    /**
     * @notice Emitted when a new cutting board has been queued.
     * @param valPubkey The validator's pubkey.
     * @param startBlock The block that the cutting board goes into effect.
     * @param weights The weights of the cutting board.
     */
    event QueueCuttingBoard(bytes indexed valPubkey, uint64 startBlock, Weight[] weights);

    /**
     * @notice Emitted when a new cutting board has been activated.
     * @param valPubkey The validator's pubkey.
     * @param startBlock The block that the cutting board goes into effect.
     * @param weights The weights of the cutting board.
     */
    event ActivateCuttingBoard(bytes indexed valPubkey, uint64 startBlock, Weight[] weights);

    /**
     * @notice Emitted when the governance module has set a new default cutting board.
     * @param cuttingBoard The default cutting board.
     */
    event SetDefaultCuttingBoard(CuttingBoard cuttingBoard);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Returns the active cutting board for validator with given pubkey
     * @param valPubkey The validator's pubkey.
     * @return cuttingBoard The active cutting board.
     */
    function getActiveCuttingBoard(bytes calldata valPubkey) external view returns (CuttingBoard memory);

    /**
     * @notice Returns the queued cutting board for a validator with given pubkey
     * @param valPubkey The validator's pubkey.
     * @return cuttingBoard The queued cutting board.
     */
    function getQueuedCuttingBoard(bytes calldata valPubkey) external view returns (CuttingBoard memory);

    /**
     * @notice Returns the active cutting board set by the validator with given pubkey.
     * @dev This will return active cutting board set by validators even if its not valid.
     * @param valPubkey The validator's pubkey.
     * @return cuttingBoard The cutting board.
     */
    function getSetActiveCuttingBoard(bytes calldata valPubkey) external view returns (CuttingBoard memory);

    /**
     * @notice Returns the default cutting board for validators that do not have a cutting board.
     * @return cuttingBoard The default cutting board.
     */
    function getDefaultCuttingBoard() external view returns (CuttingBoard memory);

    /**
     * @notice Returns the status of whether a queued cutting board is ready to be activated.
     * @param valPubkey The validator's pubkey.
     * @param blockNumber The block number to be queried.
     * @return isReady True if the queued cutting board is ready to be activated, false otherwise.
     */
    function isQueuedCuttingBoardReady(bytes calldata valPubkey, uint256 blockNumber) external view returns (bool);

    /**
     * @notice Returns the status of whether the BeraChef contract is ready to be used.
     * @dev This function should be used by all contracts that depend on a system call.
     * @dev This will return false if the governance module has not set a default cutting board yet.
     * @return isReady True if the BeraChef is ready to be used, false otherwise.
     */
    function isReady() external view returns (bool);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Sets the maximum number of weights per cutting board.
    function setMaxNumWeightsPerCuttingBoard(uint8 _maxNumWeightsPerCuttingBoard) external;

    /// @notice Sets the delay in blocks before a new cutting board can be queued.
    function setCuttingBoardBlockDelay(uint64 _cuttingBoardBlockDelay) external;

    /**
     * @notice Updates the friends of the chef, the status of whether a receiver is whitelisted or not.
     * @notice The caller of this function must be the governance module account.
     * @param receiver The address to remove or add as a friend of the chef.
     * @param isFriend The whitelist status; true if the receiver is being whitelisted, false otherwise.
     */
    function updateFriendsOfTheChef(address receiver, bool isFriend) external;

    /**
     * @notice Sets the default cutting board for validators that do not have a cutting board.
     * @dev The caller of this function must be the governance module account.
     * @param cuttingBoard The default cutting board.
     */
    function setDefaultCuttingBoard(CuttingBoard calldata cuttingBoard) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          SETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Add a new cutting board to the queue for validator with given pubkey.
     * @dev The weights of the cutting board must add up to 100% or 1e4. Only whitelisted pools may be used as well.
     * @param valPubkey The validator's pubkey.
     * @param startBlock The block that the cutting board goes into effect.
     * @param weights The weights of the cutting board.
     */
    function queueNewCuttingBoard(bytes calldata valPubkey, uint64 startBlock, Weight[] calldata weights) external;

    /// @notice Activates the queued cutting board for a validator if its ready.
    /// @dev Should be called by the distribution contract.
    /// @param valPubkey The validator's pubkey.
    /// @param blockNumber The block number being processed.
    function activateReadyQueuedCuttingBoard(bytes calldata valPubkey, uint256 blockNumber) external;
}
