// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRecipientRegistry} from "../../src/interfaces/IRecipientRegistry.sol";

contract MockRecipientRegistry is IRecipientRegistry {
    address[] public recipients;
    mapping(address => RecipientInfo) public recipientInfo;
    address[] public queuedAdditions;
    address[] public queuedRemovals;
    
    function addRecipient(address recipient) external {
        recipients.push(recipient);
        recipientInfo[recipient] = RecipientInfo({
            recipientAddress: recipient,
            isActive: true,
            addedBlock: block.number,
            removedBlock: 0,
            metadata: ""
        });
        emit RecipientAdded(recipient, block.number);
    }
    
    function removeRecipient(address recipient) external {
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == recipient) {
                recipients[i] = recipients[recipients.length - 1];
                recipients.pop();
                recipientInfo[recipient].isActive = false;
                recipientInfo[recipient].removedBlock = block.number;
                emit RecipientRemoved(recipient, block.number);
                break;
            }
        }
    }
    
    function getActiveRecipients() external view override returns (address[] memory) {
        return recipients;
    }
    
    function isActiveRecipient(address recipient) external view override returns (bool) {
        return recipientInfo[recipient].isActive;
    }
    
    function getRecipientInfo(address recipient) external view override returns (RecipientInfo memory) {
        return recipientInfo[recipient];
    }
    
    function queueRecipientAddition(address recipient, string memory metadata) external override {
        queuedAdditions.push(recipient);
        recipientInfo[recipient].metadata = metadata;
        emit RecipientQueued(recipient, true, block.number + 100);
    }
    
    function queueRecipientRemoval(address recipient) external override {
        queuedRemovals.push(recipient);
        emit RecipientQueued(recipient, false, block.number + 100);
    }
    
    function processQueuedChanges() external override {
        for (uint256 i = 0; i < queuedAdditions.length; i++) {
            recipients.push(queuedAdditions[i]);
            recipientInfo[queuedAdditions[i]].isActive = true;
            recipientInfo[queuedAdditions[i]].addedBlock = block.number;
            emit QueuedChangeProcessed(queuedAdditions[i], true);
        }
        
        for (uint256 i = 0; i < queuedRemovals.length; i++) {
            for (uint256 j = 0; j < recipients.length; j++) {
                if (recipients[j] == queuedRemovals[i]) {
                    recipients[j] = recipients[recipients.length - 1];
                    recipients.pop();
                    recipientInfo[queuedRemovals[i]].isActive = false;
                    recipientInfo[queuedRemovals[i]].removedBlock = block.number;
                    emit QueuedChangeProcessed(queuedRemovals[i], false);
                    break;
                }
            }
        }
        
        delete queuedAdditions;
        delete queuedRemovals;
    }
    
    function getActiveRecipientCount() external view override returns (uint256) {
        return recipients.length;
    }
    
    function getQueuedAdditions() external view override returns (address[] memory) {
        return queuedAdditions;
    }
    
    function getQueuedRemovals() external view override returns (address[] memory) {
        return queuedRemovals;
    }
    
    function cancelQueuedAddition(address recipient) external override {
        for (uint256 i = 0; i < queuedAdditions.length; i++) {
            if (queuedAdditions[i] == recipient) {
                queuedAdditions[i] = queuedAdditions[queuedAdditions.length - 1];
                queuedAdditions.pop();
                break;
            }
        }
    }
    
    function cancelQueuedRemoval(address recipient) external override {
        for (uint256 i = 0; i < queuedRemovals.length; i++) {
            if (queuedRemovals[i] == recipient) {
                queuedRemovals[i] = queuedRemovals[queuedRemovals.length - 1];
                queuedRemovals.pop();
                break;
            }
        }
    }
    
    function emergencyAddRecipient(address recipient) external override {
        recipients.push(recipient);
        recipientInfo[recipient].isActive = true;
        recipientInfo[recipient].addedBlock = block.number;
    }
    
    function emergencyRemoveRecipient(address recipient) external override {
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == recipient) {
                recipients[i] = recipients[recipients.length - 1];
                recipients.pop();
                recipientInfo[recipient].isActive = false;
                recipientInfo[recipient].removedBlock = block.number;
                break;
            }
        }
    }
}