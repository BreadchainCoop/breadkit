// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title AdminRecipientRegistry
/// @notice Simple admin-controlled registry for managing yield recipients
/// @dev Admin can directly add or remove recipients without any voting or delays
contract AdminRecipientRegistry is OwnableUpgradeable {
    
    // Active recipients
    address[] public recipients;
    
    // Mapping to check if address is an active recipient
    mapping(address => bool) public isRecipient;
    
    // Events
    event RecipientAdded(address indexed recipient);
    event RecipientRemoved(address indexed recipient);
    
    // Errors
    error InvalidRecipient();
    error RecipientAlreadyExists();
    error RecipientNotFound();

    /// @notice Initialize the registry
    /// @param admin The admin address
    function initialize(address admin) public initializer {
        __Ownable_init(admin);
    }

    /// @notice Add a recipient
    /// @param recipient Address to add
    function addRecipient(address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidRecipient();
        if (isRecipient[recipient]) revert RecipientAlreadyExists();
        
        recipients.push(recipient);
        isRecipient[recipient] = true;
        
        emit RecipientAdded(recipient);
    }

    /// @notice Add multiple recipients in one transaction
    /// @param _recipients Array of addresses to add
    function addRecipients(address[] calldata _recipients) external onlyOwner {
        for (uint256 i = 0; i < _recipients.length; i++) {
            address recipient = _recipients[i];
            if (recipient == address(0)) revert InvalidRecipient();
            if (isRecipient[recipient]) revert RecipientAlreadyExists();
            
            recipients.push(recipient);
            isRecipient[recipient] = true;
            
            emit RecipientAdded(recipient);
        }
    }

    /// @notice Remove a recipient
    /// @param recipient Address to remove
    function removeRecipient(address recipient) external onlyOwner {
        if (!isRecipient[recipient]) revert RecipientNotFound();
        
        isRecipient[recipient] = false;
        
        // Remove from array
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == recipient) {
                recipients[i] = recipients[recipients.length - 1];
                recipients.pop();
                break;
            }
        }
        
        emit RecipientRemoved(recipient);
    }

    /// @notice Remove multiple recipients in one transaction
    /// @param _recipients Array of addresses to remove
    function removeRecipients(address[] calldata _recipients) external onlyOwner {
        for (uint256 i = 0; i < _recipients.length; i++) {
            address recipient = _recipients[i];
            if (!isRecipient[recipient]) revert RecipientNotFound();
            
            isRecipient[recipient] = false;
            
            // Remove from array
            for (uint256 j = 0; j < recipients.length; j++) {
                if (recipients[j] == recipient) {
                    recipients[j] = recipients[recipients.length - 1];
                    recipients.pop();
                    break;
                }
            }
            
            emit RecipientRemoved(recipient);
        }
    }

    /// @notice Get all active recipients
    /// @return Array of active recipient addresses
    function getRecipients() external view returns (address[] memory) {
        return recipients;
    }

    /// @notice Get count of active recipients
    /// @return Number of active recipients
    function getRecipientCount() external view returns (uint256) {
        return recipients.length;
    }

    /// @notice Transfer admin rights to a new address
    /// @param newAdmin The new admin address
    function transferAdmin(address newAdmin) external onlyOwner {
        transferOwnership(newAdmin);
    }
}