// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IFixedSplitModule
/// @notice Interface for the fixed split module that manages fixed yield allocations
/// @dev This module handles the fixed portion of yield distribution
interface IFixedSplitModule {
    /// @notice Calculates the fixed distribution amounts
    /// @param totalYield The total yield available for distribution
    /// @return fixedAmount The amount allocated for fixed distribution
    /// @return votedAmount The remaining amount for voted distribution
    function calculateFixedDistribution(uint256 totalYield) external view returns (uint256 fixedAmount, uint256 votedAmount);

    /// @notice Calculates required tokens for the distribution
    /// @return The amount of tokens required to mint
    function calculateRequiredTokensForDistribution() external view returns (uint256);

    /// @notice Prepares tokens for distribution
    /// @dev Called before distribution to ensure tokens are ready
    function prepareTokensForDistribution() external;

    /// @notice Gets the fixed split configuration
    /// @return divisor The divisor used for fixed split calculation
    function getFixedSplitDivisor() external view returns (uint256 divisor);

    /// @notice Sets the fixed split divisor
    /// @param divisor The new divisor value
    function setFixedSplitDivisor(uint256 divisor) external;

    /// @notice Gets recipients eligible for fixed distribution
    /// @return Array of recipient addresses
    function getFixedSplitRecipients() external view returns (address[] memory);
}