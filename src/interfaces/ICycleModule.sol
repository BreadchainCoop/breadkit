// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ICycleModule
/// @notice Interface for the cycle module
/// @dev Simplified interface focusing only on cycle timing without distribution logic
interface ICycleModule {
    /// @notice Struct containing information about a cycle
    struct CycleInfo {
        uint256 cycleNumber;
        uint256 startBlock;
        uint256 endBlock;
        uint256 blocksRemaining;
        bool isActive;
    }

    /// @notice Gets the current cycle number
    /// @return The current cycle number
    function getCurrentCycle() external view returns (uint256);

    /// @notice Checks if the current cycle has completed
    /// @return Whether the cycle timing allows for transition
    function isCycleComplete() external view returns (bool);

    /// @notice Starts a new cycle
    /// @dev Only callable by authorized contracts
    function startNewCycle() external;

    /// @notice Gets information about the current cycle
    /// @return Information about the current cycle
    function getCycleInfo() external view returns (CycleInfo memory);

    /// @notice Gets the number of blocks until the next cycle
    /// @return The number of blocks remaining in the current cycle
    function getBlocksUntilNextCycle() external view returns (uint256);

    /// @notice Gets the progress of the current cycle as a percentage
    /// @return The cycle progress (0-100)
    function getCycleProgress() external view returns (uint256);

    /// @notice Updates the cycle length for future cycles
    /// @param newCycleLength The new cycle length in blocks
    function updateCycleLength(uint256 newCycleLength) external;
}
