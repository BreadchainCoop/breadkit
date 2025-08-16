// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ICycleManager
/// @notice Interface for managing distribution cycles and their timing
/// @dev Manages the timing and state of distribution cycles
interface ICycleManager {
    /// @notice Resolves whether distribution should occur
    /// @dev Contains all logic to determine if conditions are met
    /// @return canExec Whether execution should proceed
    /// @return execPayload The encoded function call data
    function resolveDistribution() external view returns (bool canExec, bytes memory execPayload);

    /// @notice Executes the distribution
    /// @dev Handles all distribution logic including yield calculation and transfers
    function executeDistribution() external;

    /// @notice Checks if the distribution is ready to be executed
    /// @return ready Whether the distribution conditions are met
    function isDistributionReady() external view returns (bool ready);

    /// @notice Gets the number of blocks until the next cycle
    /// @return blocks The number of blocks remaining until the next cycle
    function getBlocksUntilNextCycle() external view returns (uint256 blocks);

    /// @notice Starts a new distribution cycle
    /// @dev Called after a successful distribution to reset the cycle
    function startNewCycle() external;

    /// @notice Gets the current cycle information
    /// @return cycleNumber The current cycle number
    /// @return startBlock The block number when the current cycle started
    /// @return endBlock The block number when the current cycle should end
    function getCycleInfo() external view returns (uint256 cycleNumber, uint256 startBlock, uint256 endBlock);

    /// @notice Sets the cycle length in blocks
    /// @param _cycleLength The number of blocks in each cycle
    function setCycleLength(uint256 _cycleLength) external;

    /// @notice Gets the current cycle length
    /// @return The number of blocks in each cycle
    function getCycleLength() external view returns (uint256);

    /// @notice Gets the last distribution block
    /// @return The block number of the last distribution
    function getLastDistributionBlock() external view returns (uint256);

    /// @notice Gets the current votes in the cycle
    /// @return The total number of votes cast
    function getCurrentVotes() external view returns (uint256);

    /// @notice Gets the available yield for distribution
    /// @return The amount of yield available
    function getAvailableYield() external view returns (uint256);
}
