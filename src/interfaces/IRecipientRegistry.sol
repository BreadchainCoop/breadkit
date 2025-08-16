// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IRecipientRegistry
/// @notice Interface for managing yield recipients
/// @dev This interface defines the recipient registry functionality for the voting system
interface IRecipientRegistry {
    /// @notice Gets the list of active recipients for the current cycle
    /// @return Array of recipient addresses
    function getActiveRecipients() external view returns (address[] memory);

    /// @notice Gets the number of active recipients
    /// @return The count of active recipients
    function getActiveRecipientsCount() external view returns (uint256);
}
