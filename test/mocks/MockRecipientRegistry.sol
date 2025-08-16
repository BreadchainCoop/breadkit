// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRecipientRegistry} from "../../src/interfaces/IRecipientRegistry.sol";

/// @title MockRecipientRegistry
/// @notice Mock implementation of IRecipientRegistry for testing
contract MockRecipientRegistry is IRecipientRegistry {
    address[] public activeRecipients;
    address[] public queuedAdditions;
    address[] public queuedRemovals;

    mapping(address => bool) public isRecipient;
    mapping(address => RecipientInfo) public recipientInfo;

    struct RecipientInfo {
        string name;
        string description;
        uint256 addedAt;
    }

    constructor(address[] memory _initialRecipients) {
        for (uint256 i = 0; i < _initialRecipients.length; i++) {
            activeRecipients.push(_initialRecipients[i]);
            isRecipient[_initialRecipients[i]] = true;
            recipientInfo[_initialRecipients[i]] =
                RecipientInfo({name: "Test Recipient", description: "Test Description", addedAt: block.number});
        }
    }

    function getActiveRecipients() external view override returns (address[] memory) {
        return activeRecipients;
    }

    function getActiveRecipientsCount() external view override returns (uint256) {
        return activeRecipients.length;
    }

    // Internal queue management functions (not part of interface)
    function getQueuedAdditions() external view returns (address[] memory) {
        return queuedAdditions;
    }

    function getQueuedRemovals() external view returns (address[] memory) {
        return queuedRemovals;
    }

    function queueRecipientAddition(address recipient) external {
        queuedAdditions.push(recipient);
    }

    function queueRecipientRemoval(address recipient) external {
        require(isRecipient[recipient], "Not a recipient");
        queuedRemovals.push(recipient);
    }

    function processQueuedChanges() external {
        // Process additions
        for (uint256 i = 0; i < queuedAdditions.length; i++) {
            address recipient = queuedAdditions[i];
            if (!isRecipient[recipient]) {
                activeRecipients.push(recipient);
                isRecipient[recipient] = true;
                recipientInfo[recipient] =
                    RecipientInfo({name: "New Recipient", description: "New Description", addedAt: block.number});
            }
        }

        // Process removals
        for (uint256 i = 0; i < queuedRemovals.length; i++) {
            address recipient = queuedRemovals[i];
            if (isRecipient[recipient]) {
                isRecipient[recipient] = false;
                // Remove from activeRecipients array
                for (uint256 j = 0; j < activeRecipients.length; j++) {
                    if (activeRecipients[j] == recipient) {
                        activeRecipients[j] = activeRecipients[activeRecipients.length - 1];
                        activeRecipients.pop();
                        break;
                    }
                }
            }
        }

        // Clear queues
        delete queuedAdditions;
        delete queuedRemovals;
    }

    function validateRecipient(address recipient) external view override returns (bool) {
        return recipient != address(0);
    }

    function getRecipientInfo(address recipient)
        external
        view
        override
        returns (string memory name, string memory description, uint256 addedAt)
    {
        RecipientInfo memory info = recipientInfo[recipient];
        return (info.name, info.description, info.addedAt);
    }

    // Helper function for testing
    function setActiveRecipients(address[] memory _recipients) external {
        delete activeRecipients;
        for (uint256 i = 0; i < _recipients.length; i++) {
            activeRecipients.push(_recipients[i]);
            isRecipient[_recipients[i]] = true;
        }
    }
}
