// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { Utils } from "../libraries/Utils.sol";
import { IPOLErrors } from "./interfaces/IPOLErrors.sol";

abstract contract RootHelper is IPOLErrors {
    using Utils for bytes4;

    /// @notice Emitted when the block is advanced.
    /// @param blockNum The block number of the block just actioned upon.
    event AdvancedBlock(uint256 blockNum);

    /// @notice Emitted when the block count is skipped.
    /// @param prev The previous last actioned block number.
    /// @param current The current last actioned block number.
    event BlockCountReset(uint256 prev, uint256 current);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTANTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The length of the history buffer.
    uint256 private constant HISTORY_BUFFER_LENGTH = 8191;
    /// @dev The beacon roots contract address.
    address private constant BEACON_ROOT_ADDRESS = 0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02;

    /// @dev The last block number that was processed.
    uint256 private _lastProcessedBlock;

    /// @notice Resets the next actionable block number to _block, used when out of the beacon root buffer.
    /// @dev This action should be permissioned to prevent unauthorized actors from modifying the block number
    /// inappropriately.
    /// @param _block The block number to reset to.
    function resetCount(uint256 _block) public virtual {
        _resetCount(_block);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC READ FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Gets the next block to be rewarded.
    /// @dev This returns the greater of last processed block + 1, or current block number - 8190 as that is
    /// the limitation on number of blocks that can be queried, and actioned upon.
    /// @return blockNum The block number of the next block to be invoked.
    function getNextActionableBlock() public view returns (uint256) {
        unchecked {
            return FixedPointMathLib.max(
                _lastProcessedBlock, FixedPointMathLib.zeroFloorSub(block.number, HISTORY_BUFFER_LENGTH)
            ) + 1;
        }
    }

    /// @notice Gets the last block that was actioned upon.
    /// @return blockNum The block number of the last block that was actioned upon.
    function getLastActionedBlock() public view returns (uint256) {
        return _lastProcessedBlock;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Increments `_lastProcessedBlock` to the processing block.
    /// @dev Emits `AdvancedBlock` event after incrementing.
    function _incrementBlock(uint256 processingBlock) internal {
        // Increment and emit event.
        _lastProcessedBlock = processingBlock;
        emit AdvancedBlock(processingBlock);
    }

    /// @dev Resets the next actionable block to the inputted block number
    /// @param _block The block number to reset actionable block to.
    function _resetCount(uint256 _block) internal {
        // Reverts if the block number is in the future.
        if (_block > block.number) {
            BlockDoesNotExist.selector.revertWith();
        }
        // Reverts if the block number is before the next actionable block.
        if (_block < getNextActionableBlock()) {
            BlockNotInBuffer.selector.revertWith();
        }

        unchecked {
            // Emit an event to capture a block count reset.
            emit BlockCountReset(_lastProcessedBlock, _block - 1);

            // Sets the actionable block to the inputted block.
            _lastProcessedBlock = _block - 1;
        }
    }
}
