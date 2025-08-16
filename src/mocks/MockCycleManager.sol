// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/ICycleManager.sol";
import "../interfaces/IDistributionManager.sol";

/// @title MockCycleManager
/// @notice Mock implementation of ICycleManager for cycle management
/// @dev Manages cycle timing and provides automation data
contract MockCycleManager is ICycleManager {
    uint256 public cycleLength;
    uint256 public lastDistributionBlock;
    uint256 public currentCycleNumber;

    address public distributionManager;

    constructor(uint256 _cycleLength) {
        cycleLength = _cycleLength;
        lastDistributionBlock = block.number;
        currentCycleNumber = 1;
    }

    function setDistributionManager(address _distributionManager) external {
        distributionManager = _distributionManager;
    }

    /// @notice Gets the automation data for execution
    /// @dev Returns encoded function call data for automation providers
    function getAutomationData() external view override returns (bytes memory execPayload) {
        // Return the execution payload for the distribution manager
        if (distributionManager != address(0)) {
            return abi.encodeWithSelector(IDistributionManager.executeDistribution.selector);
        }
        return new bytes(0);
    }

    /// @notice Updates the last distribution block
    /// @dev Called by distribution manager after successful distribution
    function updateLastDistributionBlock() external {
        require(msg.sender == distributionManager, "Only distribution manager");
        lastDistributionBlock = block.number;
        currentCycleNumber++;
    }

    /// @notice Gets blocks until next cycle
    function getBlocksUntilNextCycle() external view override returns (uint256 blocks) {
        uint256 nextCycleBlock = lastDistributionBlock + cycleLength;
        if (block.number >= nextCycleBlock) {
            return 0;
        }
        return nextCycleBlock - block.number;
    }

    /// @notice Starts a new cycle (called after distribution)
    function startNewCycle() external override {
        // This is handled in executeDistribution
        // Kept for interface compatibility
    }

    /// @notice Gets cycle information
    function getCycleInfo()
        external
        view
        override
        returns (uint256 cycleNumber, uint256 startBlock, uint256 endBlock)
    {
        return (currentCycleNumber, lastDistributionBlock, lastDistributionBlock + cycleLength);
    }

    /// @notice Sets the cycle length
    function setCycleLength(uint256 _cycleLength) external override {
        require(_cycleLength > 0, "Invalid cycle length");
        cycleLength = _cycleLength;
    }

    /// @notice Gets the cycle length
    function getCycleLength() external view override returns (uint256) {
        return cycleLength;
    }

    /// @notice Gets the last distribution block
    function getLastDistributionBlock() external view override returns (uint256) {
        return lastDistributionBlock;
    }
}
