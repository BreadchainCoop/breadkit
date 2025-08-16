// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IRecipientRegistry.sol";
import "./QueueManager.sol";

/// @title RecipientRegistry
/// @notice Core contract for managing yield recipients with time-delayed changes
/// @dev Implements secure recipient management with validation and governance controls
contract RecipientRegistry is IRecipientRegistry, QueueManager, OwnableUpgradeable {
    mapping(address => Recipient) private _recipients;
    address[] private _activeRecipientAddresses;
    mapping(uint256 => QueuedChange) private _queuedChanges;

    uint256 private constant MAX_RECIPIENTS = 50;
    uint256 private constant PERCENTAGE_PRECISION = 10000; // 100.00%

    /// @notice Initialize the registry with default delay
    /// @param owner_ The owner address
    /// @param delay_ Initial delay for changes (in seconds)
    function initialize(address owner_, uint256 delay_) public initializer {
        __Ownable_init(owner_);
        _initializeQueue(delay_);
    }

    /// @notice Queue a new recipient addition
    function queueAddRecipient(address recipient, uint256 percentage, string calldata metadata)
        external
        onlyOwner
        returns (uint256 changeId)
    {
        if (recipient == address(0)) revert InvalidRecipient();
        if (percentage == 0 || percentage > PERCENTAGE_PRECISION) revert InvalidPercentage();
        if (_recipients[recipient].isActive) revert RecipientAlreadyExists();
        if (_activeRecipientAddresses.length >= MAX_RECIPIENTS) revert InvalidRecipient();

        changeId = _enqueue();

        _queuedChanges[changeId] = QueuedChange({
            changeType: 0, // add
            recipient: recipient,
            percentage: percentage,
            metadata: metadata,
            executeAfter: _queue[changeId].executeAfter,
            executed: false,
            cancelled: false
        });

        emit RecipientQueued(changeId, 0, recipient, _queue[changeId].executeAfter);
    }

    /// @notice Queue a recipient removal
    function queueRemoveRecipient(address recipient) external onlyOwner returns (uint256 changeId) {
        if (!_recipients[recipient].isActive) revert RecipientNotFound();

        changeId = _enqueue();

        _queuedChanges[changeId] = QueuedChange({
            changeType: 1, // remove
            recipient: recipient,
            percentage: 0,
            metadata: "",
            executeAfter: _queue[changeId].executeAfter,
            executed: false,
            cancelled: false
        });

        emit RecipientQueued(changeId, 1, recipient, _queue[changeId].executeAfter);
    }

    /// @notice Queue a recipient update
    function queueUpdateRecipient(address recipient, uint256 percentage, string calldata metadata)
        external
        onlyOwner
        returns (uint256 changeId)
    {
        if (!_recipients[recipient].isActive) revert RecipientNotFound();
        if (percentage == 0 || percentage > PERCENTAGE_PRECISION) revert InvalidPercentage();

        changeId = _enqueue();

        _queuedChanges[changeId] = QueuedChange({
            changeType: 2, // update
            recipient: recipient,
            percentage: percentage,
            metadata: metadata,
            executeAfter: _queue[changeId].executeAfter,
            executed: false,
            cancelled: false
        });

        emit RecipientQueued(changeId, 2, recipient, _queue[changeId].executeAfter);
    }

    /// @notice Execute a queued change after delay period
    function executeChange(uint256 changeId) external {
        if (!_canExecute(changeId)) revert ItemNotReady();

        QueuedChange storage change = _queuedChanges[changeId];
        if (change.executed) revert ItemAlreadyExecuted();
        if (change.cancelled) revert ChangeIsCancelled();

        if (change.changeType == 0) {
            _addRecipient(change.recipient, change.percentage, change.metadata);
        } else if (change.changeType == 1) {
            _removeRecipient(change.recipient);
        } else if (change.changeType == 2) {
            _updateRecipient(change.recipient, change.percentage, change.metadata);
        }

        change.executed = true;
        _markExecuted(changeId);

        if (!validatePercentages()) revert TotalPercentageExceeds100();

        emit ChangeExecuted(changeId);
    }

    /// @notice Cancel a queued change
    function cancelChange(uint256 changeId) external onlyOwner {
        QueuedChange storage change = _queuedChanges[changeId];
        if (change.executed) revert ItemAlreadyExecuted();
        if (change.cancelled) revert ChangeIsCancelled();

        change.cancelled = true;
        _cancelQueueItem(changeId);

        emit ChangeCancelled(changeId);
    }

    /// @notice Internal function to add recipient
    function _addRecipient(address recipient, uint256 percentage, string memory metadata) private {
        _recipients[recipient] = Recipient({
            addr: recipient,
            percentage: percentage,
            metadata: metadata,
            isActive: true,
            addedAt: block.timestamp
        });

        _activeRecipientAddresses.push(recipient);
        emit RecipientAdded(recipient, percentage, metadata);
    }

    /// @notice Internal function to remove recipient
    function _removeRecipient(address recipient) private {
        delete _recipients[recipient];

        // Remove from active addresses array
        for (uint256 i = 0; i < _activeRecipientAddresses.length; i++) {
            if (_activeRecipientAddresses[i] == recipient) {
                _activeRecipientAddresses[i] = _activeRecipientAddresses[_activeRecipientAddresses.length - 1];
                _activeRecipientAddresses.pop();
                break;
            }
        }

        emit RecipientRemoved(recipient);
    }

    /// @notice Internal function to update recipient
    function _updateRecipient(address recipient, uint256 percentage, string memory metadata) private {
        Recipient storage r = _recipients[recipient];
        r.percentage = percentage;
        r.metadata = metadata;

        emit RecipientUpdated(recipient, percentage, metadata);
    }

    /// @notice Get all active recipients
    function getActiveRecipients() external view returns (Recipient[] memory) {
        uint256 length = _activeRecipientAddresses.length;
        Recipient[] memory activeRecipients = new Recipient[](length);

        for (uint256 i = 0; i < length; i++) {
            activeRecipients[i] = _recipients[_activeRecipientAddresses[i]];
        }

        return activeRecipients;
    }

    /// @notice Get a specific recipient's details
    function getRecipient(address recipient) external view returns (Recipient memory) {
        return _recipients[recipient];
    }

    /// @notice Get a queued change details
    function getQueuedChange(uint256 changeId) external view returns (QueuedChange memory) {
        return _queuedChanges[changeId];
    }

    /// @notice Get all pending changes
    function getPendingChanges() external view returns (uint256[] memory) {
        return _getPendingIds();
    }

    /// @notice Check if an address is an active recipient
    function isActiveRecipient(address recipient) external view returns (bool) {
        return _recipients[recipient].isActive;
    }

    /// @notice Get the current time delay for changes
    function getDelay() external view returns (uint256) {
        return _getDelay();
    }

    /// @notice Set a new time delay for changes
    function setDelay(uint256 newDelay) external onlyOwner {
        uint256 oldDelay = _delay;
        _updateDelay(newDelay);
        emit DelayUpdated(oldDelay, newDelay);
    }

    /// @notice Validate that total percentages don't exceed 100%
    function validatePercentages() public view returns (bool) {
        uint256 totalPercentage = 0;

        for (uint256 i = 0; i < _activeRecipientAddresses.length; i++) {
            totalPercentage += _recipients[_activeRecipientAddresses[i]].percentage;
        }

        return totalPercentage <= PERCENTAGE_PRECISION;
    }

    /// @notice Get total allocated percentage
    function getTotalAllocatedPercentage() external view returns (uint256) {
        uint256 totalPercentage = 0;

        for (uint256 i = 0; i < _activeRecipientAddresses.length; i++) {
            totalPercentage += _recipients[_activeRecipientAddresses[i]].percentage;
        }

        return totalPercentage;
    }

    /// @notice Get number of active recipients
    function getActiveRecipientCount() external view returns (uint256) {
        return _activeRecipientAddresses.length;
    }
}
