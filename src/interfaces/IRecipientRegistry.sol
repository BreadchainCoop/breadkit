// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IRecipientRegistry
/// @notice Interface for managing yield recipients with simple queueing
/// @dev Based on the Breadchain YieldDistributor queueing model
interface IRecipientRegistry {
    
    // Events
    event RecipientQueued(address indexed recipient, bool isAddition);
    event RecipientAdded(address indexed recipient);
    event RecipientRemoved(address indexed recipient);
    event QueueProcessed(uint256 added, uint256 removed);
    
    // Errors
    error InvalidRecipient();
    error RecipientAlreadyExists();
    error RecipientNotFound();
    error RecipientAlreadyQueued();

    /// @notice Queue a recipient for addition
    /// @param recipient Address to add
    function queueRecipientAddition(address recipient) external;

    /// @notice Queue a recipient for removal
    /// @param recipient Address to remove
    function queueRecipientRemoval(address recipient) external;

    /// @notice Process all queued changes
    function processQueue() external;

    /// @notice Clear the addition queue
    function clearAdditionQueue() external;

    /// @notice Clear the removal queue
    function clearRemovalQueue() external;

    /// @notice Get all active recipients
    /// @return Array of active recipient addresses
    function getRecipients() external view returns (address[] memory);

    /// @notice Get queued additions
    /// @return Array of addresses queued for addition
    function getQueuedAdditions() external view returns (address[] memory);

    /// @notice Get queued removals
    /// @return Array of addresses queued for removal
    function getQueuedRemovals() external view returns (address[] memory);

    /// @notice Get count of active recipients
    /// @return Number of active recipients
    function getRecipientCount() external view returns (uint256);

    /// @notice Check if address is an active recipient
    /// @param recipient Address to check
    /// @return True if active recipient
    function isRecipient(address recipient) external view returns (bool);

    /// @notice Check if address is queued for addition
    /// @param recipient Address to check
    /// @return True if queued for addition
    function isQueuedForAddition(address recipient) external view returns (bool);

    /// @notice Check if address is queued for removal
    /// @param recipient Address to check
    /// @return True if queued for removal
    function isQueuedForRemoval(address recipient) external view returns (bool);
}