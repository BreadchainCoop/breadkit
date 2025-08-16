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

    /// @notice Checks if an address is an active recipient
    /// @param recipient The address to check
    /// @return True if the address is an active recipient
    function isActiveRecipient(address recipient) external view returns (bool);

    /// @notice Gets recipients queued for addition
    /// @return Array of addresses queued for addition
    function getQueuedAdditions() external view returns (address[] memory);

    /// @notice Gets recipients queued for removal
    /// @return Array of addresses queued for removal
    function getQueuedRemovals() external view returns (address[] memory);

    /// @notice Queues a recipient for addition in the next cycle
    /// @param recipient The recipient address to add
    function queueRecipientAddition(address recipient) external;

    /// @notice Queues a recipient for removal in the next cycle
    /// @param recipient The recipient address to remove
    function queueRecipientRemoval(address recipient) external;

    /// @notice Processes all queued changes (additions and removals)
    /// @dev Should be called at the end of each cycle
    function processQueuedChanges() external;

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
