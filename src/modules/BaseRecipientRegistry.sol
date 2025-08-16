// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title BaseRecipientRegistry
/// @notice Abstract base contract for managing yield recipients with queued changes
/// @dev Provides common queue management functionality for recipient registries
abstract contract BaseRecipientRegistry is OwnableUpgradeable {
    /// @notice Array of active recipient addresses
    /// @dev This array contains all currently active recipients who can receive yield
    address[] public recipients;

    /// @notice Array of addresses queued for addition to the recipient list
    /// @dev These addresses will be added when updateRecipients() is called
    address[] public queuedRecipientsForAddition;

    /// @notice Array of addresses queued for removal from the recipient list
    /// @dev These addresses will be removed when updateRecipients() is called
    address[] public queuedRecipientsForRemoval;

    /// @notice Mapping to quickly check if an address is an active recipient
    /// @dev Maps recipient address to true if active, false otherwise
    mapping(address => bool) public isRecipient;

    // Events
    /// @notice Emitted when a recipient is successfully added to the registry
    /// @param recipient The address of the newly added recipient
    event RecipientAdded(address indexed recipient);

    /// @notice Emitted when a recipient is successfully removed from the registry
    /// @param recipient The address of the removed recipient
    event RecipientRemoved(address indexed recipient);

    /// @notice Emitted when a recipient is queued for addition or removal
    /// @param recipient The address being queued
    /// @param isAddition True if queued for addition, false for removal
    event RecipientQueued(address indexed recipient, bool isAddition);

    /// @notice Emitted when the queue is processed and recipients are updated
    /// @param added Number of recipients added
    /// @param removed Number of recipients removed
    event QueueProcessed(uint256 added, uint256 removed);

    // Errors
    /// @notice Thrown when attempting to add the zero address as a recipient
    error InvalidRecipient();

    /// @notice Thrown when attempting to add a recipient that already exists in the registry
    error RecipientAlreadyExists();

    /// @notice Thrown when attempting to remove a recipient that doesn't exist in the registry
    error RecipientNotFound();

    /// @notice Thrown when attempting to queue a recipient that is already queued
    error RecipientAlreadyQueued();

    /// @notice Internal function to queue a recipient for addition
    /// @param recipient Address to add to the queue
    /// @dev This is an internal function that should be called by derived contracts
    /// @dev Validates the recipient address and checks for duplicates before queuing
    /// @dev Emits RecipientQueued event with isAddition=true
    /// @dev Access control should be implemented in the calling public function
    function _queueForAddition(address recipient) internal {
        if (recipient == address(0)) revert InvalidRecipient();
        if (isRecipient[recipient]) revert RecipientAlreadyExists();

        // Check if already queued to prevent duplicates
        for (uint256 i = 0; i < queuedRecipientsForAddition.length; i++) {
            if (queuedRecipientsForAddition[i] == recipient) {
                revert RecipientAlreadyQueued();
            }
        }

        queuedRecipientsForAddition.push(recipient);
        emit RecipientQueued(recipient, true);
    }

    /// @notice Internal function to queue a recipient for removal
    /// @param recipient Address to remove from the active recipients
    /// @dev This is an internal function that should be called by derived contracts
    /// @dev Validates that the recipient exists and isn't already queued for removal
    /// @dev Emits RecipientQueued event with isAddition=false
    /// @dev Access control should be implemented in the calling public function
    function _queueForRemoval(address recipient) internal {
        if (!isRecipient[recipient]) revert RecipientNotFound();

        // Check if already queued for removal to prevent duplicates
        for (uint256 i = 0; i < queuedRecipientsForRemoval.length; i++) {
            if (queuedRecipientsForRemoval[i] == recipient) {
                revert RecipientAlreadyQueued();
            }
        }

        queuedRecipientsForRemoval.push(recipient);
        emit RecipientQueued(recipient, false);
    }

    /// @notice Process all queued changes and update recipients
    /// @dev This function can be called by the distributor manager or anyone
    /// @dev This is the main external interface for processing pending recipient changes
    function processQueue() external {
        _processQueue();
    }

    /// @notice Internal function to process the queue and update recipients
    /// @dev Processes all queued additions and removals, then clears the queues
    /// @dev Emits RecipientAdded/RecipientRemoved for each change and QueueProcessed at the end
    function _processQueue() internal {
        uint256 addedCount = queuedRecipientsForAddition.length;
        uint256 removedCount = 0;

        // Add all queued recipients
        for (uint256 i = 0; i < queuedRecipientsForAddition.length; i++) {
            address recipient = queuedRecipientsForAddition[i];
            recipients.push(recipient);
            isRecipient[recipient] = true;
            emit RecipientAdded(recipient);
        }

        // Process removals by rebuilding the recipients array
        if (queuedRecipientsForRemoval.length > 0) {
            address[] memory oldRecipients = recipients;
            delete recipients;

            for (uint256 i = 0; i < oldRecipients.length; i++) {
                address recipient = oldRecipients[i];
                bool shouldRemove = false;

                // Check if this recipient should be removed
                for (uint256 j = 0; j < queuedRecipientsForRemoval.length; j++) {
                    if (recipient == queuedRecipientsForRemoval[j]) {
                        shouldRemove = true;
                        isRecipient[recipient] = false;
                        removedCount++;
                        emit RecipientRemoved(recipient);
                        break;
                    }
                }

                // Keep recipient if not marked for removal
                if (!shouldRemove) {
                    recipients.push(recipient);
                }
            }
        }

        // Clear both queues after processing
        delete queuedRecipientsForAddition;
        delete queuedRecipientsForRemoval;

        emit QueueProcessed(addedCount, removedCount);
    }

    /// @notice Clear the addition queue without processing
    /// @dev Only owner can clear the queue. Use this to cancel all pending additions
    /// @dev This will remove all addresses from the addition queue without adding them
    function clearAdditionQueue() external onlyOwner {
        delete queuedRecipientsForAddition;
    }

    /// @notice Clear the removal queue without processing
    /// @dev Only owner can clear the queue. Use this to cancel all pending removals
    /// @dev This will remove all addresses from the removal queue without removing them
    function clearRemovalQueue() external onlyOwner {
        delete queuedRecipientsForRemoval;
    }

    /// @notice Get all active recipients
    /// @dev Returns a copy of the recipients array
    /// @return recipients_ Array of active recipient addresses
    function getRecipients() external view returns (address[] memory recipients_) {
        return recipients;
    }

    /// @notice Get all addresses queued for addition
    /// @dev Returns a copy of the addition queue array
    /// @return queuedAdditions Array of addresses queued for addition
    function getQueuedAdditions() external view returns (address[] memory queuedAdditions) {
        return queuedRecipientsForAddition;
    }

    /// @notice Get all addresses queued for removal
    /// @dev Returns a copy of the removal queue array
    /// @return queuedRemovals Array of addresses queued for removal
    function getQueuedRemovals() external view returns (address[] memory queuedRemovals) {
        return queuedRecipientsForRemoval;
    }

    /// @notice Get the total count of active recipients
    /// @dev More gas efficient than calling getRecipients().length
    /// @return count Number of active recipients
    function getRecipientCount() external view returns (uint256 count) {
        return recipients.length;
    }

    /// @notice Check if an address is queued for addition
    /// @param recipient Address to check in the addition queue
    /// @return isQueued True if the address is queued for addition, false otherwise
    function isQueuedForAddition(address recipient) external view returns (bool isQueued) {
        for (uint256 i = 0; i < queuedRecipientsForAddition.length; i++) {
            if (queuedRecipientsForAddition[i] == recipient) {
                return true;
            }
        }
        return false;
    }

    /// @notice Check if an address is queued for removal
    /// @param recipient Address to check in the removal queue
    /// @return isQueued True if the address is queued for removal, false otherwise
    function isQueuedForRemoval(address recipient) external view returns (bool isQueued) {
        for (uint256 i = 0; i < queuedRecipientsForRemoval.length; i++) {
            if (queuedRecipientsForRemoval[i] == recipient) {
                return true;
            }
        }
        return false;
    }

}
