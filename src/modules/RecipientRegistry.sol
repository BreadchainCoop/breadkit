// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title RecipientRegistry
/// @notice Simple registry for managing yield recipients with queued changes
/// @dev Based on the Breadchain YieldDistributor queueing model
contract RecipientRegistry is OwnableUpgradeable {
    
    // Active recipients
    address[] public recipients;
    
    // Queued additions and removals
    address[] public queuedRecipientsForAddition;
    address[] public queuedRecipientsForRemoval;
    
    // Mapping to check if address is an active recipient
    mapping(address => bool) public isRecipient;
    
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

    /// @notice Initialize the registry
    /// @param owner_ The owner address
    function initialize(address owner_) public initializer {
        __Ownable_init(owner_);
    }

    /// @notice Queue a recipient for addition
    /// @param recipient Address to add
    function queueRecipientAddition(address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidRecipient();
        if (isRecipient[recipient]) revert RecipientAlreadyExists();
        
        // Check if already queued
        for (uint256 i = 0; i < queuedRecipientsForAddition.length; i++) {
            if (queuedRecipientsForAddition[i] == recipient) {
                revert RecipientAlreadyQueued();
            }
        }
        
        queuedRecipientsForAddition.push(recipient);
        emit RecipientQueued(recipient, true);
    }

    /// @notice Queue a recipient for removal
    /// @param recipient Address to remove
    function queueRecipientRemoval(address recipient) external onlyOwner {
        if (!isRecipient[recipient]) revert RecipientNotFound();
        
        // Check if already queued for removal
        for (uint256 i = 0; i < queuedRecipientsForRemoval.length; i++) {
            if (queuedRecipientsForRemoval[i] == recipient) {
                revert RecipientAlreadyQueued();
            }
        }
        
        queuedRecipientsForRemoval.push(recipient);
        emit RecipientQueued(recipient, false);
    }

    /// @notice Process all queued changes
    /// @dev Can be called by anyone to process the queue
    function processQueue() external {
        _updateRecipients();
    }

    /// @notice Internal function to update recipients based on queued changes
    function _updateRecipients() internal {
        uint256 addedCount = queuedRecipientsForAddition.length;
        uint256 removedCount = 0;
        
        // Add all queued recipients
        for (uint256 i = 0; i < queuedRecipientsForAddition.length; i++) {
            address recipient = queuedRecipientsForAddition[i];
            recipients.push(recipient);
            isRecipient[recipient] = true;
            emit RecipientAdded(recipient);
        }

        // Process removals
        if (queuedRecipientsForRemoval.length > 0) {
            address[] memory oldRecipients = recipients;
            delete recipients;
            
            for (uint256 i = 0; i < oldRecipients.length; i++) {
                address recipient = oldRecipients[i];
                bool shouldRemove = false;
                
                for (uint256 j = 0; j < queuedRecipientsForRemoval.length; j++) {
                    if (recipient == queuedRecipientsForRemoval[j]) {
                        shouldRemove = true;
                        isRecipient[recipient] = false;
                        removedCount++;
                        emit RecipientRemoved(recipient);
                        break;
                    }
                }
                
                if (!shouldRemove) {
                    recipients.push(recipient);
                }
            }
        }
        
        // Clear queues
        delete queuedRecipientsForAddition;
        delete queuedRecipientsForRemoval;
        
        emit QueueProcessed(addedCount, removedCount);
    }

    /// @notice Clear the addition queue
    /// @dev Only owner can clear the queue
    function clearAdditionQueue() external onlyOwner {
        delete queuedRecipientsForAddition;
    }

    /// @notice Clear the removal queue
    /// @dev Only owner can clear the queue
    function clearRemovalQueue() external onlyOwner {
        delete queuedRecipientsForRemoval;
    }

    /// @notice Get all active recipients
    /// @return Array of active recipient addresses
    function getRecipients() external view returns (address[] memory) {
        return recipients;
    }

    /// @notice Get queued additions
    /// @return Array of addresses queued for addition
    function getQueuedAdditions() external view returns (address[] memory) {
        return queuedRecipientsForAddition;
    }

    /// @notice Get queued removals
    /// @return Array of addresses queued for removal
    function getQueuedRemovals() external view returns (address[] memory) {
        return queuedRecipientsForRemoval;
    }

    /// @notice Get count of active recipients
    /// @return Number of active recipients
    function getRecipientCount() external view returns (uint256) {
        return recipients.length;
    }

    /// @notice Check if address is queued for addition
    /// @param recipient Address to check
    /// @return bool True if queued for addition
    function isQueuedForAddition(address recipient) external view returns (bool) {
        for (uint256 i = 0; i < queuedRecipientsForAddition.length; i++) {
            if (queuedRecipientsForAddition[i] == recipient) {
                return true;
            }
        }
        return false;
    }

    /// @notice Check if address is queued for removal
    /// @param recipient Address to check
    /// @return bool True if queued for removal
    function isQueuedForRemoval(address recipient) external view returns (bool) {
        for (uint256 i = 0; i < queuedRecipientsForRemoval.length; i++) {
            if (queuedRecipientsForRemoval[i] == recipient) {
                return true;
            }
        }
        return false;
    }
}