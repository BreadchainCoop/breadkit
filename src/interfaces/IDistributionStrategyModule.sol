// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionStrategy} from "./IDistributionStrategy.sol";

/// @title IDistributionStrategyModule
/// @notice Interface for managing yield distribution with multiple strategies
/// @dev Orchestrates distribution between equal and voting-based strategies
interface IDistributionStrategyModule {
    /// @notice Emitted when the split ratio is updated
    /// @param oldDivisor Previous divisor
    /// @param newDivisor New divisor
    event SplitRatioUpdated(uint256 oldDivisor, uint256 newDivisor);

    /// @notice Emitted when strategies are updated
    /// @param equalStrategy Address of equal distribution strategy
    /// @param votingStrategy Address of voting distribution strategy
    event StrategiesUpdated(address equalStrategy, address votingStrategy);

    /// @notice Emitted when yield is distributed
    /// @param totalYield Total yield amount
    /// @param equalAmount Amount sent to equal distribution
    /// @param votingAmount Amount sent to voting distribution
    event YieldDistributed(uint256 totalYield, uint256 equalAmount, uint256 votingAmount);

    /// @notice Distributes yield between strategies according to split ratio
    /// @param totalYield Total amount of yield to distribute
    function distributeYield(uint256 totalYield) external;

    /// @notice Updates the split ratio between strategies
    /// @param divisor New divisor (e.g., 2 for 50/50 split)
    function updateSplitRatio(uint256 divisor) external;

    /// @notice Gets the equal distribution strategy
    /// @return Address of the equal distribution strategy
    function equalDistributionStrategy() external view returns (IDistributionStrategy);

    /// @notice Gets the voting distribution strategy
    /// @return Address of the voting distribution strategy
    function votingDistributionStrategy() external view returns (IDistributionStrategy);

    /// @notice Gets the current split divisor
    /// @return Current divisor value
    function splitDivisor() external view returns (uint256);

    /// @notice Calculates how yield would be split
    /// @param totalYield Total yield to split
    /// @return equalAmount Amount for equal distribution
    /// @return votingAmount Amount for voting distribution
    function calculateSplit(uint256 totalYield) external view returns (uint256 equalAmount, uint256 votingAmount);
}
