// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IRecipientRegistry
/// @notice Interface for managing yield recipients with time-delayed queue system
/// @dev Provides secure recipient management through validation and time delays
interface IRecipientRegistry {
    struct Recipient {
        address addr;
        uint256 percentage;
        string metadata;
        bool isActive;
        uint256 addedAt;
    }

    struct QueuedChange {
        uint256 changeType; // 0: add, 1: remove, 2: update
        address recipient;
        uint256 percentage;
        string metadata;
        uint256 executeAfter;
        bool executed;
        bool cancelled;
    }

    event RecipientQueued(uint256 indexed changeId, uint256 changeType, address recipient, uint256 executeAfter);
    event RecipientAdded(address indexed recipient, uint256 percentage, string metadata);
    event RecipientRemoved(address indexed recipient);
    event RecipientUpdated(address indexed recipient, uint256 percentage, string metadata);
    event ChangeExecuted(uint256 indexed changeId);
    event ChangeCancelled(uint256 indexed changeId);
    event DelayUpdated(uint256 oldDelay, uint256 newDelay);

    error InvalidRecipient();
    error InvalidPercentage();
    error RecipientAlreadyExists();
    error RecipientNotFound();
    error TotalPercentageExceeds100();
    error UnauthorizedAccess();
    error QueueEmpty();

    /// @notice Queue a new recipient addition
    /// @param recipient Address of the recipient to add
    /// @param percentage Percentage allocation for the recipient
    /// @param metadata Additional information about the recipient
    /// @return changeId Unique identifier for the queued change
    function queueAddRecipient(address recipient, uint256 percentage, string calldata metadata)
        external
        returns (uint256 changeId);

    /// @notice Queue a recipient removal
    /// @param recipient Address of the recipient to remove
    /// @return changeId Unique identifier for the queued change
    function queueRemoveRecipient(address recipient) external returns (uint256 changeId);

    /// @notice Queue a recipient update
    /// @param recipient Address of the recipient to update
    /// @param percentage New percentage allocation
    /// @param metadata New metadata
    /// @return changeId Unique identifier for the queued change
    function queueUpdateRecipient(address recipient, uint256 percentage, string calldata metadata)
        external
        returns (uint256 changeId);

    /// @notice Execute a queued change after delay period
    /// @param changeId Identifier of the change to execute
    function executeChange(uint256 changeId) external;

    /// @notice Cancel a queued change
    /// @param changeId Identifier of the change to cancel
    function cancelChange(uint256 changeId) external;

    /// @notice Get all active recipients
    /// @return Array of active recipients
    function getActiveRecipients() external view returns (Recipient[] memory);

    /// @notice Get a specific recipient's details
    /// @param recipient Address of the recipient
    /// @return Recipient details
    function getRecipient(address recipient) external view returns (Recipient memory);

    /// @notice Get a queued change details
    /// @param changeId Identifier of the change
    /// @return QueuedChange details
    function getQueuedChange(uint256 changeId) external view returns (QueuedChange memory);

    /// @notice Get all pending changes
    /// @return Array of pending change IDs
    function getPendingChanges() external view returns (uint256[] memory);

    /// @notice Check if an address is an active recipient
    /// @param recipient Address to check
    /// @return bool True if active recipient
    function isActiveRecipient(address recipient) external view returns (bool);

    /// @notice Get the current time delay for changes
    /// @return uint256 Current delay in seconds
    function getDelay() external view returns (uint256);

    /// @notice Set a new time delay for changes
    /// @param newDelay New delay in seconds
    function setDelay(uint256 newDelay) external;

    /// @notice Validate that total percentages don't exceed 100%
    /// @return bool True if valid
    function validatePercentages() external view returns (bool);
}