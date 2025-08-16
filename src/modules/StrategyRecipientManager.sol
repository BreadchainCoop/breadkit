// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title StrategyRecipientManager
/// @notice Manages recipients and their percentage allocations for distribution strategies
/// @dev Provides recipient management functionality with validation
contract StrategyRecipientManager is Ownable {
    error ZeroAddress();
    error RecipientNotFound();
    error RecipientAlreadyExists();
    error InvalidPercentage();
    error PercentagesMismatch();
    error EmptyRecipients();
    error TooManyRecipients();

    uint256 public constant PERCENTAGE_BASE = 10000; // 100% = 10000 basis points
    uint256 public constant MAX_RECIPIENTS = 100;

    struct Recipient {
        address addr;
        uint256 percentage;
        bool isActive;
        string label;
    }

    mapping(address => uint256) public recipientIndex;
    Recipient[] public recipients;
    uint256 public activeRecipientCount;

    event RecipientAdded(address indexed recipient, uint256 percentage, string label);
    event RecipientRemoved(address indexed recipient);
    event RecipientUpdated(address indexed recipient, uint256 oldPercentage, uint256 newPercentage);
    event RecipientLabelUpdated(address indexed recipient, string newLabel);
    event RecipientsReset();

    constructor() {
        _initializeOwner(msg.sender);
    }

    /// @notice Adds a new recipient with percentage allocation
    /// @param recipient Address of the recipient
    /// @param percentage Percentage allocation in basis points
    /// @param label Optional label for the recipient
    function addRecipient(address recipient, uint256 percentage, string memory label) 
        external 
        onlyOwner 
    {
        if (recipient == address(0)) revert ZeroAddress();
        if (percentage == 0 || percentage > PERCENTAGE_BASE) revert InvalidPercentage();
        if (activeRecipientCount >= MAX_RECIPIENTS) revert TooManyRecipients();
        
        if (recipients.length > 0 && recipientIndex[recipient] < recipients.length) {
            if (recipients[recipientIndex[recipient]].addr == recipient) {
                revert RecipientAlreadyExists();
            }
        }
        
        recipients.push(Recipient({
            addr: recipient,
            percentage: percentage,
            isActive: true,
            label: label
        }));
        
        recipientIndex[recipient] = recipients.length - 1;
        activeRecipientCount++;
        
        emit RecipientAdded(recipient, percentage, label);
    }

    /// @notice Removes a recipient from the list
    /// @param recipient Address of the recipient to remove
    function removeRecipient(address recipient) external onlyOwner {
        uint256 index = recipientIndex[recipient];
        
        if (index >= recipients.length || recipients[index].addr != recipient) {
            revert RecipientNotFound();
        }
        
        recipients[index].isActive = false;
        activeRecipientCount--;
        
        emit RecipientRemoved(recipient);
    }

    /// @notice Updates the percentage allocation for a recipient
    /// @param recipient Address of the recipient
    /// @param newPercentage New percentage allocation
    function updatePercentage(address recipient, uint256 newPercentage) 
        external 
        onlyOwner 
    {
        if (newPercentage == 0 || newPercentage > PERCENTAGE_BASE) revert InvalidPercentage();
        
        uint256 index = recipientIndex[recipient];
        
        if (index >= recipients.length || recipients[index].addr != recipient) {
            revert RecipientNotFound();
        }
        
        if (!recipients[index].isActive) revert RecipientNotFound();
        
        uint256 oldPercentage = recipients[index].percentage;
        recipients[index].percentage = newPercentage;
        
        emit RecipientUpdated(recipient, oldPercentage, newPercentage);
    }

    /// @notice Updates the label for a recipient
    /// @param recipient Address of the recipient
    /// @param newLabel New label for the recipient
    function updateLabel(address recipient, string memory newLabel) 
        external 
        onlyOwner 
    {
        uint256 index = recipientIndex[recipient];
        
        if (index >= recipients.length || recipients[index].addr != recipient) {
            revert RecipientNotFound();
        }
        
        if (!recipients[index].isActive) revert RecipientNotFound();
        
        recipients[index].label = newLabel;
        
        emit RecipientLabelUpdated(recipient, newLabel);
    }

    /// @notice Batch updates recipients and their percentages
    /// @param newRecipients Array of recipient addresses
    /// @param newPercentages Array of percentage allocations
    /// @param labels Array of labels for recipients
    function batchUpdateRecipients(
        address[] calldata newRecipients,
        uint256[] calldata newPercentages,
        string[] calldata labels
    ) external onlyOwner {
        if (newRecipients.length != newPercentages.length) revert PercentagesMismatch();
        if (newRecipients.length != labels.length) revert PercentagesMismatch();
        if (newRecipients.length == 0) revert EmptyRecipients();
        if (newRecipients.length > MAX_RECIPIENTS) revert TooManyRecipients();
        
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < newPercentages.length; i++) {
            if (newRecipients[i] == address(0)) revert ZeroAddress();
            if (newPercentages[i] == 0 || newPercentages[i] > PERCENTAGE_BASE) {
                revert InvalidPercentage();
            }
            totalPercentage += newPercentages[i];
        }
        
        if (totalPercentage != PERCENTAGE_BASE) revert PercentagesMismatch();
        
        delete recipients;
        activeRecipientCount = 0;
        
        for (uint256 i = 0; i < newRecipients.length; i++) {
            recipients.push(Recipient({
                addr: newRecipients[i],
                percentage: newPercentages[i],
                isActive: true,
                label: labels[i]
            }));
            
            recipientIndex[newRecipients[i]] = i;
            activeRecipientCount++;
        }
        
        emit RecipientsReset();
    }

    /// @notice Gets all active recipients
    /// @return activeRecipients Array of active recipient data
    function getActiveRecipients() 
        external 
        view 
        returns (Recipient[] memory activeRecipients) 
    {
        activeRecipients = new Recipient[](activeRecipientCount);
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i].isActive) {
                activeRecipients[currentIndex] = recipients[i];
                currentIndex++;
            }
        }
    }

    /// @notice Gets active recipient addresses and percentages
    /// @return addresses Array of active recipient addresses
    /// @return percentages Array of percentage allocations
    function getActiveRecipientsData() 
        external 
        view 
        returns (address[] memory addresses, uint256[] memory percentages) 
    {
        addresses = new address[](activeRecipientCount);
        percentages = new uint256[](activeRecipientCount);
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i].isActive) {
                addresses[currentIndex] = recipients[i].addr;
                percentages[currentIndex] = recipients[i].percentage;
                currentIndex++;
            }
        }
    }

    /// @notice Validates that active recipients' percentages sum to 100%
    /// @return isValid True if configuration is valid
    function validateRecipients() external view returns (bool isValid) {
        if (activeRecipientCount == 0) return false;
        
        uint256 totalPercentage = 0;
        
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i].isActive) {
                totalPercentage += recipients[i].percentage;
            }
        }
        
        return totalPercentage == PERCENTAGE_BASE;
    }

    /// @notice Gets the total percentage allocated to active recipients
    /// @return total Sum of all active recipient percentages
    function getTotalPercentage() external view returns (uint256 total) {
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i].isActive) {
                total += recipients[i].percentage;
            }
        }
    }
}