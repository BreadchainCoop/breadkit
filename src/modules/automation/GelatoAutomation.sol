// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AutomationBase.sol";

/// @title GelatoAutomation
/// @notice Gelato Network compatible automation implementation
/// @dev Implements Gelato automation interface for yield distribution
contract GelatoAutomation is AutomationBase {
    constructor(address _distributionManager) AutomationBase(_distributionManager) {}

    /// @notice Gelato-compatible resolver function
    /// @dev Called by Gelato executors to check if work needs to be performed
    /// @return canExec Whether execution can proceed
    /// @return execPayload The calldata to execute
    function checker() external view returns (bool canExec, bytes memory execPayload) {
        canExec = isDistributionReady();
        execPayload = canExec ? getAutomationData() : new bytes(0);
    }

    /// @notice Gelato-compatible execution function
    /// @dev Called by Gelato executors when checker returns true
    /// @param execData The data for execution (not used but can be for validation)
    function execute(bytes calldata execData) external {
        executeDistribution();
    }
}