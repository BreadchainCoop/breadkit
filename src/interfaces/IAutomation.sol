// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAutomation
/// @notice Interface for automation providers to implement
/// @dev Standardizes automation provider interactions for multi-provider redundancy
interface IAutomation {
    /// @notice Check if automation execution condition is met
    /// @return canExecute Whether the condition is met
    /// @return executionData Encoded data to pass to execute function
    function checkCondition() external view returns (bool canExecute, bytes memory executionData);

    /// @notice Execute the automation task
    /// @param data Encoded execution data from checkCondition
    function execute(bytes calldata data) external;

    /// @notice Check if the provider is currently active
    /// @return Whether the provider is active and ready
    function isProviderActive() external view returns (bool);

    /// @notice Set the cycle manager address
    /// @param cycleManager Address of the cycle manager contract
    function setCycleManager(address cycleManager) external;
}