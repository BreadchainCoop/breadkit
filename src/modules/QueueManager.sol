// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title QueueManager
/// @notice Utility contract for managing time-delayed queues
/// @dev Provides queue management functionality for the RecipientRegistry
abstract contract QueueManager {
    struct QueueItem {
        uint256 executeAfter;
        bool executed;
        bool cancelled;
    }

    mapping(uint256 => QueueItem) internal _queue;
    uint256[] internal _pendingIds;
    uint256 internal _nextQueueId;
    uint256 internal _delay;

    uint256 internal constant MIN_DELAY = 1 days;
    uint256 internal constant MAX_DELAY = 30 days;

    event QueueItemAdded(uint256 indexed itemId, uint256 executeAfter);
    event QueueItemExecuted(uint256 indexed itemId);
    event QueueItemCancelled(uint256 indexed itemId);

    error InvalidDelay();
    error ItemNotReady();
    error ItemAlreadyExecuted();
    error ChangeIsCancelled();
    error ItemNotFound();

    /// @notice Initialize queue manager with delay
    /// @param delay_ Initial delay in seconds
    function _initializeQueue(uint256 delay_) internal {
        if (delay_ < MIN_DELAY || delay_ > MAX_DELAY) {
            revert InvalidDelay();
        }
        _delay = delay_;
    }

    /// @notice Add item to queue
    /// @return itemId Unique identifier for queued item
    function _enqueue() internal returns (uint256 itemId) {
        itemId = _nextQueueId++;
        uint256 executeAfter = block.timestamp + _delay;
        
        _queue[itemId] = QueueItem({
            executeAfter: executeAfter,
            executed: false,
            cancelled: false
        });
        
        _pendingIds.push(itemId);
        emit QueueItemAdded(itemId, executeAfter);
    }

    /// @notice Check if item can be executed
    /// @param itemId Item to check
    function _canExecute(uint256 itemId) internal view returns (bool) {
        QueueItem memory item = _queue[itemId];
        
        if (item.executeAfter == 0) revert ItemNotFound();
        if (item.executed) revert ItemAlreadyExecuted();
        if (item.cancelled) revert ChangeIsCancelled();
        if (block.timestamp < item.executeAfter) revert ItemNotReady();
        
        return true;
    }

    /// @notice Mark item as executed
    /// @param itemId Item to mark
    function _markExecuted(uint256 itemId) internal {
        _queue[itemId].executed = true;
        _removePendingId(itemId);
        emit QueueItemExecuted(itemId);
    }

    /// @notice Cancel queued item
    /// @param itemId Item to cancel
    function _cancelQueueItem(uint256 itemId) internal {
        QueueItem storage item = _queue[itemId];
        
        if (item.executeAfter == 0) revert ItemNotFound();
        if (item.executed) revert ItemAlreadyExecuted();
        if (item.cancelled) revert ChangeIsCancelled();
        
        item.cancelled = true;
        _removePendingId(itemId);
        emit QueueItemCancelled(itemId);
    }

    /// @notice Remove ID from pending list
    /// @param itemId Item to remove
    function _removePendingId(uint256 itemId) private {
        uint256 length = _pendingIds.length;
        for (uint256 i = 0; i < length; i++) {
            if (_pendingIds[i] == itemId) {
                _pendingIds[i] = _pendingIds[length - 1];
                _pendingIds.pop();
                break;
            }
        }
    }

    /// @notice Get pending item IDs
    /// @return Array of pending IDs
    function _getPendingIds() internal view returns (uint256[] memory) {
        return _pendingIds;
    }

    /// @notice Update delay for future items
    /// @param newDelay New delay in seconds
    function _updateDelay(uint256 newDelay) internal {
        if (newDelay < MIN_DELAY || newDelay > MAX_DELAY) {
            revert InvalidDelay();
        }
        _delay = newDelay;
    }

    /// @notice Get current delay
    /// @return Current delay in seconds
    function _getDelay() internal view returns (uint256) {
        return _delay;
    }

    /// @notice Clean up expired cancelled/executed items from pending list
    function _cleanupPendingList() internal {
        uint256[] memory tempIds = new uint256[](_pendingIds.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < _pendingIds.length; i++) {
            uint256 itemId = _pendingIds[i];
            QueueItem memory item = _queue[itemId];
            
            if (!item.executed && !item.cancelled) {
                tempIds[count++] = itemId;
            }
        }
        
        delete _pendingIds;
        for (uint256 i = 0; i < count; i++) {
            _pendingIds.push(tempIds[i]);
        }
    }
}