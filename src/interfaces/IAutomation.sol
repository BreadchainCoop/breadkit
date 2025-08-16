// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAutomation
/// @notice Interface for automation providers that can trigger protocol operations
/// @dev Standard interface for all automation providers (Chainlink, Gelato, etc.)
interface IAutomation {
    /// @notice Checks if the automation condition is met
    /// @return needsExecution Whether the automation should execute
    /// @return performData The encoded data to pass to the execution function
    function checkCondition() external view returns (bool needsExecution, bytes memory performData);

    /// @notice Executes the automation task
    /// @param data The encoded data for execution
    function execute(bytes calldata data) external;

    /// @notice Checks if the provider is currently active
    /// @return Whether the provider is active and can execute
    function isProviderActive() external view returns (bool);

    /// @notice Sets the cycle manager address
    /// @param _cycleManager The address of the cycle manager
    function setCycleManager(address _cycleManager) external;

    /// @notice Gets the cycle manager address
    /// @return The address of the cycle manager
    function getCycleManager() external view returns (address);
}
