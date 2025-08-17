// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AutomationBase.sol";

// TODO: Re-enable when Chainlink dependency is properly installed
// import {AutomationCompatibleInterface} from
//     "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

// Temporary interface stub
interface AutomationCompatibleInterface {
    function checkUpkeep(bytes calldata checkData) external returns (bool upkeepNeeded, bytes memory performData);
    function performUpkeep(bytes calldata performData) external;
}

/// @title ChainlinkAutomation
/// @notice Chainlink Keeper compatible automation implementation
/// @dev Implements Chainlink automation interface for yield distribution
contract ChainlinkAutomation is AutomationBase, AutomationCompatibleInterface {
    
    // ============ Constructor ============
    constructor(address _owner) AutomationBase(_owner) {}

    // ============ Chainlink Automation ============

    /// @notice Checks if upkeep is needed (Chainlink Keeper interface)
    /// @param checkData Data passed by Chainlink Keeper network
    /// @return upkeepNeeded Whether upkeep is needed
    /// @return performData Data to pass to performUpkeep
    function checkUpkeep(bytes calldata checkData) 
        external 
        view 
        override 
        returns (bool upkeepNeeded, bytes memory performData) 
    {
        upkeepNeeded = isDistributionReady();
        performData = checkData; // Pass through the data
        return (upkeepNeeded, performData);
    }

    /// @notice Performs the upkeep (Chainlink Keeper interface)
    /// @dev performData parameter is unused but required by interface
    function performUpkeep(bytes calldata /* performData */) external override {
        executeDistribution();
    }
}