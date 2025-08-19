// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionStrategy} from "./IDistributionStrategy.sol";

/// @title IDistributionStrategyModule
/// @notice Interface for managing yield distribution to strategies
/// @dev Receives yield and distributes to configured strategies
interface IDistributionStrategyModule {
    /// @notice Emitted when a strategy is added
    /// @param strategy Address of the strategy
    event StrategyAdded(address strategy);

    /// @notice Emitted when a strategy is removed
    /// @param strategy Address of the strategy
    event StrategyRemoved(address strategy);

    /// @notice Emitted when yield is distributed to a strategy
    /// @param strategy Address of the strategy
    /// @param amount Amount distributed
    event YieldDistributed(address strategy, uint256 amount);

    /// @notice Distributes yield to a specific strategy
    /// @param strategy Address of the strategy to distribute to
    /// @param amount Amount to distribute
    function distributeToStrategy(address strategy, uint256 amount) external;

    /// @notice Adds a strategy to the module
    /// @param strategy Address of the strategy to add
    function addStrategy(address strategy) external;

    /// @notice Removes a strategy from the module
    /// @param strategy Address of the strategy to remove
    function removeStrategy(address strategy) external;

    /// @notice Checks if an address is a registered strategy
    /// @param strategy Address to check
    /// @return True if the address is a registered strategy
    function isStrategy(address strategy) external view returns (bool);

    /// @notice Gets all registered strategies
    /// @return Array of strategy addresses
    function getStrategies() external view returns (address[] memory);
}
