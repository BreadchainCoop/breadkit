// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IDistributionManager.sol";
import "../interfaces/IDistributionModule.sol";

/// @title MockDistributionManager
/// @notice Mock implementation of IDistributionManager for testing
/// @dev Contains distribution readiness logic and execution
contract MockDistributionManager is IDistributionManager {
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

    /// @notice Checks if distribution is ready
    function isDistributionReady() public view override returns (bool ready) {
        // Check if enough blocks have passed
        if (block.number < lastDistributionBlock + cycleLength) {
            return false;
        }

        // Check if there are votes
        if (currentVotes == 0) {
            return false;
        }

        // Check if there's sufficient yield
        if (availableYield < minYieldRequired) {
            return false;
        }

        // Check if system is enabled
        if (!isEnabled) {
            return false;
        }

        return true;
    }

    /// @notice Gets the automation data for execution
    /// @dev Returns encoded function call data for automation providers
    function getAutomationData() external view override returns (bytes memory execPayload) {
        // Return the execution payload if conditions are met
        if (isDistributionReady()) {
            return abi.encodeWithSelector(this.executeDistribution.selector);
        }
        return new bytes(0);
    }

    /// @notice Executes the distribution
    /// @dev Handles all distribution logic
    function executeDistribution() external override {
        // Verify conditions again
        require(block.number >= lastDistributionBlock + cycleLength, "Too soon");
        require(currentVotes > 0, "No votes");
        require(availableYield >= minYieldRequired, "Insufficient yield");
        require(isEnabled, "System disabled");

        // Update state
        lastDistributionBlock = block.number;
        currentCycleNumber++;

        // Call distribution module to handle the actual distribution
        distributionModule.distribute();

        // Emit event
        emit DistributionExecuted(block.number, availableYield, currentVotes);

        // Reset for next cycle
        currentVotes = 0;
        availableYield = 0;
    }

    // Helper functions for testing
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

    function getLastDistributionBlock() external view returns (uint256) {
        return lastDistributionBlock;
    }

    function getCycleInfo() external view returns (uint256 cycleNumber, uint256 startBlock, uint256 endBlock) {
        return (currentCycleNumber, lastDistributionBlock, lastDistributionBlock + cycleLength);
    }
}
