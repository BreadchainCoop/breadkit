// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/ICycleManager.sol";
import "../interfaces/IDistributionModule.sol";

/// @title MockCycleManager
/// @notice Mock implementation of ICycleManager with all distribution logic
/// @dev Contains all the logic for determining when and how to distribute yield
contract MockCycleManager is ICycleManager {
    IDistributionModule public immutable distributionModule;

    uint256 public cycleLength;
    uint256 public lastDistributionBlock;
    uint256 public currentCycleNumber;
    uint256 public currentVotes;
    uint256 public minYieldRequired;
    uint256 public availableYield;

    bool public isEnabled = true;

    event DistributionExecuted(uint256 blockNumber, uint256 yield, uint256 votes);

    constructor(address _distributionModule, uint256 _cycleLength) {
        require(_distributionModule != address(0), "Invalid distribution module");
        distributionModule = IDistributionModule(_distributionModule);
        cycleLength = _cycleLength;
        lastDistributionBlock = block.number;
        currentCycleNumber = 1;
        minYieldRequired = 1000; // Example minimum yield
    }

    /// @notice Resolves whether distribution should occur
    /// @dev Implements the same logic as Breadchain's resolveYieldDistribution
    function resolveDistribution() external view override returns (bool canExec, bytes memory execPayload) {
        // Check if enough blocks have passed
        if (block.number < lastDistributionBlock + cycleLength) {
            return (false, new bytes(0));
        }

        // Check if there are votes
        if (currentVotes == 0) {
            return (false, new bytes(0));
        }

        // Check if there's sufficient yield
        if (availableYield < minYieldRequired) {
            return (false, new bytes(0));
        }

        // Check if system is enabled
        if (!isEnabled) {
            return (false, new bytes(0));
        }

        // All conditions met, return true with empty payload
        return (true, new bytes(0));
    }

    /// @notice Checks if distribution is ready
    function isDistributionReady() external view override returns (bool ready) {
        (bool canExec,) = this.resolveDistribution();
        return canExec;
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
        // This would handle starting a new cycle
        // Implementation depends on specific requirements
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

    /// @notice Gets current votes
    function getCurrentVotes() external view override returns (uint256) {
        return currentVotes;
    }

    /// @notice Gets available yield
    function getAvailableYield() external view override returns (uint256) {
        return availableYield;
    }

    // Mock functions for testing
    function setCurrentVotes(uint256 _votes) external {
        currentVotes = _votes;
    }

    function setAvailableYield(uint256 _yield) external {
        availableYield = _yield;
    }

    function setEnabled(bool _enabled) external {
        isEnabled = _enabled;
    }

    function setMinYieldRequired(uint256 _minYield) external {
        minYieldRequired = _minYield;
    }
}
