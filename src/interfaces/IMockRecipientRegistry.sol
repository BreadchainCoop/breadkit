// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IMockRecipientRegistry
/// @notice Interface for mock recipient registry used in testing
/// @dev Simplified interface for voting module testing
interface IMockRecipientRegistry {
    /// @notice Get all currently active recipients
    /// @return Array of active recipient addresses
    function getActiveRecipients() external view returns (address[] memory);

    /// @notice Get the count of active recipients
    /// @return Number of active recipients
    function getActiveRecipientsCount() external view returns (uint256);
}
