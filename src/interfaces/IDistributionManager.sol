// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IDistributionManager
/// @notice Interface for managing distribution readiness and execution
/// @dev Handles distribution state and execution logic
interface IDistributionManager {
    /// @notice Checks if the distribution is ready to be executed
    /// @dev Contains all logic to determine if conditions are met
    /// @return ready Whether the distribution conditions are met
    function isDistributionReady() external view returns (bool ready);

    /// @notice Executes the distribution
    /// @dev Handles all distribution logic including yield calculation and transfers
    function executeDistribution() external;
}
