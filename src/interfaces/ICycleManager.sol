// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ICycleManager
/// @notice Interface for the cycle management system that orchestrates distribution cycles
/// @dev This interface standardizes interactions with the cycle management system
interface ICycleManager {
    /// @notice Struct containing information about a cycle
    struct CycleInfo {
        uint256 cycleNumber;
        uint256 startBlock;
        uint256 endBlock;
        uint256 blocksRemaining;
        bool isActive;
    }

    /// @notice Emitted when a new cycle starts
    /// @param cycleNumber The number of the new cycle
    /// @param startBlock The block number when the cycle started
    /// @param endBlock The block number when the cycle will end
    event CycleStarted(uint256 indexed cycleNumber, uint256 startBlock, uint256 endBlock);

    /// @notice Emitted when a cycle transition is validated
    /// @param cycleNumber The number of the validated cycle
    event CycleTransitionValidated(uint256 indexed cycleNumber);

    /// @notice Emitted when the cycle module is updated
    /// @param oldModule The address of the old cycle module
    /// @param newModule The address of the new cycle module
    event CycleModuleUpdated(address indexed oldModule, address indexed newModule);

    /// @notice Gets the current cycle number
    /// @return The current cycle number
    function getCurrentCycle() external view returns (uint256);

    /// @notice Checks if distribution is ready based on cycle and conditions
    /// @param votesCast The number of votes cast in the current cycle
    /// @param availableYield The amount of yield available for distribution
    /// @param minimumYield The minimum yield required for distribution
    /// @return Whether distribution is ready
    function isDistributionReady(uint256 votesCast, uint256 availableYield, uint256 minimumYield)
        external
        view
        returns (bool);

    /// @notice Starts a new cycle
    /// @dev Only callable by authorized contracts
    function startNewCycle() external;

    /// @notice Gets information about the current cycle
    /// @return Information about the current cycle
    function getCycleInfo() external view returns (CycleInfo memory);

    /// @notice Sets the cycle module implementation
    /// @param cycleModule The address of the new cycle module
    function setCycleModule(address cycleModule) external;

    /// @notice Validates if a cycle transition can occur
    /// @return Whether the cycle transition is valid
    function validateCycleTransition() external view returns (bool);
}
