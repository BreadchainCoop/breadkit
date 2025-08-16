// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IDistributionStrategyModule
/// @notice Interface for configurable yield distribution strategies
/// @dev Manages the calculation of split between fixed and voted distribution portions
interface IDistributionStrategyModule {
    /// @notice Emitted when distribution strategy is updated
    /// @param oldDivisor Previous strategy divisor
    /// @param newDivisor New strategy divisor
    event DistributionStrategyUpdated(uint256 oldDivisor, uint256 newDivisor);

    /// @notice Calculates the distribution split between fixed and voted portions
    /// @param totalYield Total yield to be distributed
    /// @return fixedAmount Amount allocated for fixed distribution
    /// @return votedAmount Amount allocated for voting-based distribution
    function calculateDistribution(uint256 totalYield)
        external
        view
        returns (uint256 fixedAmount, uint256 votedAmount);

    /// @notice Updates the distribution strategy divisor
    /// @dev Divisor determines the split (e.g., divisor=2 means 50/50 split)
    /// @param divisor New divisor value (must be > 0)
    function updateDistributionStrategy(uint256 divisor) external;

    /// @notice Validates the current strategy configuration
    /// @return isValid True if configuration is valid
    function validateStrategyConfiguration() external view returns (bool isValid);

    /// @notice Gets the current strategy divisor
    /// @return Current divisor value
    function strategyDivisor() external view returns (uint256);
}
