// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AutomationBase.sol";

/// @title ChainlinkAutomation
/// @notice Chainlink Keeper compatible automation implementation
/// @dev Implements Chainlink automation interface for yield distribution
contract ChainlinkAutomation is AutomationBase {
    constructor(address _distributionManager) AutomationBase(_distributionManager) {}

    /// @notice Chainlink-compatible upkeep check
    /// @dev Called by Chainlink nodes to check if work needs to be performed
    /// @param checkData Not used but required by Chainlink interface
    /// @return upkeepNeeded Whether upkeep is needed
    /// @return performData The data to pass to performUpkeep
    function checkUpkeep(bytes calldata checkData)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = isDistributionReady();
        performData = upkeepNeeded ? getAutomationData() : new bytes(0);
    }

    /// @notice Chainlink-compatible upkeep execution
    /// @dev Called by Chainlink nodes when checkUpkeep returns true
    /// @param performData The data returned by checkUpkeep
    function performUpkeep(bytes calldata performData) external {
        executeDistribution();
    }
}
