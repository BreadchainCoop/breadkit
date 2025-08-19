// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/interfaces/IDistributionManager.sol";

/// @title MockDistributionManagerSimple
/// @notice Mock implementation that returns true for distribution readiness every 200 blocks
/// @dev Simple mock for testing automation triggers
contract MockDistributionManagerSimple is IDistributionManager {
    uint256 public constant BLOCKS_PER_CYCLE = 200;
    uint256 public lastDistributionBlock;

    event MockDistributionExecuted(uint256 blockNumber);

    constructor() {
        lastDistributionBlock = block.number;
    }

    /// @notice Checks if distribution is ready (every 200 blocks)
    /// @return ready True if 200 blocks have passed since last distribution
    function isDistributionReady() external view override returns (bool ready) {
        return block.number >= lastDistributionBlock + BLOCKS_PER_CYCLE;
    }

    /// @notice Mock execution that simply updates the last distribution block
    function executeDistribution() external override {
        require(block.number >= lastDistributionBlock + BLOCKS_PER_CYCLE, "Not ready");

        lastDistributionBlock = block.number;

        emit MockDistributionExecuted(block.number);
    }

    /// @notice Get the number of blocks until next distribution
    /// @return blocks Number of blocks remaining
    function blocksUntilDistribution() external view returns (uint256 blocks) {
        if (block.number >= lastDistributionBlock + BLOCKS_PER_CYCLE) {
            return 0;
        }
        return (lastDistributionBlock + BLOCKS_PER_CYCLE) - block.number;
    }

    /// @notice Get the last distribution block number
    /// @return blockNumber The block number of the last distribution
    function getLastDistributionBlock() external view returns (uint256 blockNumber) {
        return lastDistributionBlock;
    }
}
