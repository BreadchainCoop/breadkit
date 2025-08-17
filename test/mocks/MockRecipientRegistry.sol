// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRecipientRegistry} from "../../src/interfaces/IRecipientRegistry.sol";

contract MockRecipientRegistry is IRecipientRegistry {
    address[] private recipients;
    mapping(address => bool) private isActive;
    
    address[] private additionQueue;
    address[] private removalQueue;
    mapping(address => bool) private inAdditionQueue;
    mapping(address => bool) private inRemovalQueue;

    function queueRecipientAddition(address recipient) external override {
        if (recipient == address(0)) revert InvalidRecipient();
        if (isActive[recipient]) revert RecipientAlreadyExists();
        if (inAdditionQueue[recipient]) revert RecipientAlreadyQueued();
        
        additionQueue.push(recipient);
        inAdditionQueue[recipient] = true;
        emit RecipientQueued(recipient, true);
    }

    function queueRecipientRemoval(address recipient) external override {
        if (!isActive[recipient]) revert RecipientNotFound();
        if (inRemovalQueue[recipient]) revert RecipientAlreadyQueued();
        
        removalQueue.push(recipient);
        inRemovalQueue[recipient] = true;
        emit RecipientQueued(recipient, false);
    }

    function processQueue() external override {
        uint256 added = 0;
        uint256 removed = 0;

        // Process additions
        for (uint256 i = 0; i < additionQueue.length; i++) {
            address recipient = additionQueue[i];
            recipients.push(recipient);
            isActive[recipient] = true;
            inAdditionQueue[recipient] = false;
            emit RecipientAdded(recipient);
            added++;
        }
        delete additionQueue;

        // Process removals
        for (uint256 i = 0; i < removalQueue.length; i++) {
            address recipient = removalQueue[i];
            isActive[recipient] = false;
            inRemovalQueue[recipient] = false;
            
            // Remove from recipients array
            for (uint256 j = 0; j < recipients.length; j++) {
                if (recipients[j] == recipient) {
                    recipients[j] = recipients[recipients.length - 1];
                    recipients.pop();
                    break;
                }
            }
            
            emit RecipientRemoved(recipient);
            removed++;
        }
        delete removalQueue;

        emit QueueProcessed(added, removed);
    }

    function clearAdditionQueue() external override {
        for (uint256 i = 0; i < additionQueue.length; i++) {
            inAdditionQueue[additionQueue[i]] = false;
        }
        delete additionQueue;
    }

    function clearRemovalQueue() external override {
        for (uint256 i = 0; i < removalQueue.length; i++) {
            inRemovalQueue[removalQueue[i]] = false;
        }
        delete removalQueue;
    }

    function getRecipients() external view override returns (address[] memory) {
        return recipients;
    }

    function getQueuedAdditions() external view override returns (address[] memory) {
        return additionQueue;
    }

    function getQueuedRemovals() external view override returns (address[] memory) {
        return removalQueue;
    }

    function getRecipientCount() external view override returns (uint256) {
        return recipients.length;
    }

    function isRecipient(address recipient) external view override returns (bool) {
        return isActive[recipient];
    }

    function isQueuedForAddition(address recipient) external view override returns (bool) {
        return inAdditionQueue[recipient];
    }

    function isQueuedForRemoval(address recipient) external view override returns (bool) {
        return inRemovalQueue[recipient];
    }
    
    // Helper function for testing - directly add recipients
    function addRecipients(address[] calldata _recipients) external {
        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && !isActive[_recipients[i]]) {
                recipients.push(_recipients[i]);
                isActive[_recipients[i]] = true;
            }
        }
    }
}