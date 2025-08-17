// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IMockRecipientRegistry
/// @notice Mock interface for testing recipient registry functionality
/// @dev This is a mock interface used only for testing the voting system
interface IMockRecipientRegistry {
    /// @notice Gets the list of active recipients for the current cycle
    /// @return Array of recipient addresses
    function getActiveRecipients() external view returns (address[] memory);

    /// @notice Gets the number of active recipients
    /// @return The count of active recipients
    function getActiveRecipientsCount() external view returns (uint256);
}
