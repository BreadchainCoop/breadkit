// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/ICycleModule.sol";
import "../interfaces/ICycleManager.sol";

/// @title FixedCycleModule
/// @notice Implements fixed-length cycles based on block numbers
/// @dev Provides deterministic cycle timing using block-based intervals
contract FixedCycleModule is ICycleModule {
    /// @notice The length of each cycle in blocks
    uint256 public cycleLength;

    /// @notice The current cycle number
    uint256 public currentCycle;

    /// @notice The block number when the current cycle started
    uint256 public lastCycleStartBlock;

    /// @notice Error thrown when cycle length is invalid
    error InvalidCycleLength();

    /// @inheritdoc ICycleModule
    function initialize(uint256 _cycleLength, uint256 _startBlock) external {
        if (_cycleLength == 0) {
            revert InvalidCycleLength();
        }

        cycleLength = _cycleLength;
        lastCycleStartBlock = _startBlock > 0 ? _startBlock : block.number;
        currentCycle = 1;
    }

    /// @inheritdoc ICycleModule
    function getCurrentCycle() external view returns (uint256) {
        return currentCycle;
    }

    /// @inheritdoc ICycleModule
    function isDistributionReady() external view returns (bool) {
        return block.number >= lastCycleStartBlock + cycleLength;
    }

    /// @inheritdoc ICycleModule
    function startNewCycle() external {
    function isDistributionReady() internal view returns (bool) {
        return block.number >= lastCycleStartBlock + cycleLength;
    }

    /// @inheritdoc ICycleModule
    function externalIsDistributionReady() external view returns (bool) {
        return isDistributionReady();
    }

    /// @inheritdoc ICycleModule
    function startNewCycle() external {
        require(isDistributionReady(), "Cycle not complete");

        currentCycle++;
        lastCycleStartBlock = block.number;

        emit NewCycleStarted(currentCycle, lastCycleStartBlock);
    }

    /// @inheritdoc ICycleModule
    function getCycleInfo() external view returns (ICycleManager.CycleInfo memory) {
        uint256 endBlock = lastCycleStartBlock + cycleLength;
        uint256 blocksRemaining = 0;

        if (block.number < endBlock) {
            blocksRemaining = endBlock - block.number;
        }

        return ICycleManager.CycleInfo({
            cycleNumber: currentCycle,
            startBlock: lastCycleStartBlock,
            endBlock: endBlock,
            blocksRemaining: blocksRemaining,
            isActive: true
        });
    }

    /// @inheritdoc ICycleModule
    function getBlocksUntilNextCycle() external view returns (uint256) {
        uint256 endBlock = lastCycleStartBlock + cycleLength;
        if (block.number >= endBlock) {
            return 0;
        }
        return endBlock - block.number;
    }

    /// @inheritdoc ICycleModule
    function getCycleProgress() external view returns (uint256) {
        uint256 blocksElapsed = block.number - lastCycleStartBlock;
        if (blocksElapsed >= cycleLength) {
            return 100;
        }
        return (blocksElapsed * 100) / cycleLength;
    }

    /// @inheritdoc ICycleModule
    function updateCycleLength(uint256 newCycleLength) external {
        if (newCycleLength == 0) {
            revert InvalidCycleLength();
        }

        uint256 oldLength = cycleLength;
        cycleLength = newCycleLength;

        emit CycleLengthUpdated(oldLength, newCycleLength);
    }
}
