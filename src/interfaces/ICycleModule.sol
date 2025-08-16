// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ICycleManager.sol";

/// @title ICycleModule
/// @notice Interface for pluggable cycle management strategies
/// @dev Implementations of this interface provide different cycle timing mechanisms
interface ICycleModule {
    /// @notice Emitted when the cycle length is updated
    /// @param oldLength The previous cycle length
    /// @param newLength The new cycle length
    event CycleLengthUpdated(uint256 oldLength, uint256 newLength);

    /// @notice Emitted when a new cycle is started
    /// @param cycleNumber The number of the new cycle
    /// @param startBlock The block when the cycle started
    event NewCycleStarted(uint256 indexed cycleNumber, uint256 startBlock);

    /// @notice Gets the current cycle number
    /// @return The current cycle number
    function getCurrentCycle() external view returns (uint256);

    /// @notice Checks if distribution is ready based on the cycle timing
    /// @return Whether the cycle timing allows for distribution
    function isDistributionReady() external view returns (bool);

    /// @notice Starts a new cycle
    /// @dev Updates internal state to begin a new cycle
    function startNewCycle() external;

    /// @notice Gets information about the current cycle
    /// @return Information about the current cycle
    function getCycleInfo() external view returns (ICycleManager.CycleInfo memory);

    /// @notice Gets the number of blocks until the next cycle
    /// @return The number of blocks remaining in the current cycle
    function getBlocksUntilNextCycle() external view returns (uint256);

    /// @notice Gets the progress of the current cycle as a percentage
    /// @return The cycle progress (0-100)
    function getCycleProgress() external view returns (uint256);

    /// @notice Initializes the cycle module
    /// @param cycleLength The length of each cycle in blocks
    /// @param startBlock The block number to start counting from
    function initialize(uint256 cycleLength, uint256 startBlock) external;

    /// @notice Updates the cycle length
    /// @param newCycleLength The new cycle length in blocks
    function updateCycleLength(uint256 newCycleLength) external;
}