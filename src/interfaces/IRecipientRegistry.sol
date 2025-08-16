// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IRecipientRegistry
/// @notice Interface for the recipient registry that manages distribution recipients
/// @dev This module handles recipient management and queuing
interface IRecipientRegistry {
    struct RecipientInfo {
        address recipientAddress;
        bool isActive;
        uint256 addedBlock;
        uint256 removedBlock;
        string metadata;
    }

    event RecipientAdded(address indexed recipient, uint256 blockNumber);
    event RecipientRemoved(address indexed recipient, uint256 blockNumber);
    event RecipientQueued(address indexed recipient, bool isAddition, uint256 executeAfterBlock);
    event QueuedChangeProcessed(address indexed recipient, bool wasAdded);

    /// @notice Gets all active recipients
    /// @return Array of active recipient addresses
    function getActiveRecipients() external view returns (address[] memory);

    /// @notice Checks if an address is an active recipient
    /// @param recipient Address to check
    /// @return Whether the address is an active recipient
    function isActiveRecipient(address recipient) external view returns (bool);

    /// @notice Gets detailed information about a recipient
    /// @param recipient Address of the recipient
    /// @return Recipient information
    function getRecipientInfo(address recipient) external view returns (RecipientInfo memory);

    /// @notice Queues a recipient for addition
    /// @param recipient Address to add
    /// @param metadata Additional information about the recipient
    function queueRecipientAddition(address recipient, string memory metadata) external;

    /// @notice Queues a recipient for removal
    /// @param recipient Address to remove
    function queueRecipientRemoval(address recipient) external;

    /// @notice Processes all queued recipient changes
    /// @dev Called at the end of each distribution cycle
    function processQueuedChanges() external;

    /// @notice Gets the count of active recipients
    /// @return Number of active recipients
    function getActiveRecipientCount() external view returns (uint256);

    /// @notice Gets all queued additions
    /// @return Array of addresses queued for addition
    function getQueuedAdditions() external view returns (address[] memory);

    /// @notice Gets all queued removals
    /// @return Array of addresses queued for removal
    function getQueuedRemovals() external view returns (address[] memory);

    /// @notice Cancels a queued addition
    /// @param recipient Address to cancel addition for
    function cancelQueuedAddition(address recipient) external;

    /// @notice Cancels a queued removal
    /// @param recipient Address to cancel removal for
    function cancelQueuedRemoval(address recipient) external;

    /// @notice Emergency function to immediately add a recipient
    /// @param recipient Address to add immediately
    function emergencyAddRecipient(address recipient) external;

    /// @notice Emergency function to immediately remove a recipient
    /// @param recipient Address to remove immediately
    function emergencyRemoveRecipient(address recipient) external;
}