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

    /// @notice Validates if a recipient address is valid
    /// @param recipient The address to validate
    /// @return True if the recipient is valid
    function validateRecipient(address recipient) external view returns (bool);

    /// @notice Gets metadata for a specific recipient
    /// @param recipient The recipient address
    /// @return name The recipient's name
    /// @return description The recipient's description
    /// @return addedAt The block number when the recipient was added
    function getRecipientInfo(address recipient)
        external
        view
        returns (string memory name, string memory description, uint256 addedAt);
}
