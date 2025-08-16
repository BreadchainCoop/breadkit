// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IDistributionStrategyModule
/// @notice Interface for configurable yield distribution strategies
/// @dev Manages the split between fixed and voted distribution portions
interface IDistributionStrategyModule {
    /// @notice Emitted when distribution strategy is updated
    /// @param oldDivisor Previous strategy divisor
    /// @param newDivisor New strategy divisor
    event DistributionStrategyUpdated(uint256 oldDivisor, uint256 newDivisor);

    /// @notice Emitted when strategy recipients are updated
    /// @param recipients Array of recipient addresses
    /// @param percentages Array of percentage allocations (basis points)
    event StrategyRecipientsUpdated(address[] recipients, uint256[] percentages);

    /// @notice Emitted when fixed distribution is executed
    /// @param recipient Address receiving the distribution
    /// @param amount Amount distributed
    event StrategyDistribution(address indexed recipient, uint256 amount);

    /// @notice Emitted when strategy distribution is complete
    /// @param totalAmount Total amount distributed
    /// @param actualDistributed Actual amount distributed after calculations
    event StrategyDistributionComplete(uint256 totalAmount, uint256 actualDistributed);

    /// @notice Calculates the distribution split between fixed and voted portions
    /// @param totalYield Total yield to be distributed
    /// @return fixedAmount Amount allocated for fixed distribution
    /// @return votedAmount Amount allocated for voting-based distribution
    function calculateDistribution(uint256 totalYield) external view returns (uint256 fixedAmount, uint256 votedAmount);

    /// @notice Updates the distribution strategy divisor
    /// @dev Divisor determines the split (e.g., divisor=2 means 50/50 split)
    /// @param divisor New divisor value (must be > 0)
    function updateDistributionStrategy(uint256 divisor) external;

    /// @notice Sets the recipients and their percentage allocations for fixed distribution
    /// @param recipients Array of recipient addresses
    /// @param percentages Array of percentage allocations (must sum to 10000 for 100%)
    function setStrategyRecipients(address[] calldata recipients, uint256[] calldata percentages) external;

    /// @notice Gets the current strategy recipients and their allocations
    /// @return recipients Array of recipient addresses
    /// @return percentages Array of percentage allocations
    function getStrategyRecipients() external view returns (address[] memory recipients, uint256[] memory percentages);

    /// @notice Gets the amount allocated for strategy distribution
    /// @param totalYield Total yield available
    /// @return Amount allocated for fixed strategy distribution
    function getStrategyAmount(uint256 totalYield) external view returns (uint256);

    /// @notice Distributes the fixed portion to strategy recipients
    /// @param amount Total amount to distribute among fixed recipients
    function distributeFixed(uint256 amount) external;

    /// @notice Validates the current strategy configuration
    /// @return isValid True if configuration is valid
    function validateStrategyConfiguration() external view returns (bool isValid);

    /// @notice Gets the current strategy divisor
    /// @return Current divisor value
    function strategyDivisor() external view returns (uint256);
}