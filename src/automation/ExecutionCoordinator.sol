// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ExecutionCoordinator
/// @notice Coordinates execution between multiple automation providers
/// @dev Prevents double-execution and manages execution locks
contract ExecutionCoordinator {
    enum ExecutionStatus {
        Idle,
        InProgress,
        Completed,
        Failed
    }

    struct ExecutionInfo {
        bool isLocked;
        address executor;
        uint256 lockTime;
        ExecutionStatus status;
        string failureReason;
    }

    ExecutionInfo public currentExecution;
    uint256 public lastSuccessfulExecution;
    uint256 public totalExecutions;
    uint256 public failedExecutions;
    uint256 public constant LOCK_TIMEOUT = 300; // 5 minutes in seconds

    event ExecutionLocked(address indexed executor, uint256 timestamp);
    event ExecutionUnlocked(address indexed executor, uint256 timestamp);
    event ExecutionCompleted(address indexed executor, uint256 timestamp);
    event ExecutionFailed(address indexed executor, string reason);

    /// @notice Lock execution to prevent concurrent execution
    /// @return success Whether the lock was acquired
    function lockExecution() external returns (bool success) {
        // Check if lock is expired
        if (currentExecution.isLocked && 
            block.timestamp > currentExecution.lockTime + LOCK_TIMEOUT) {
            // Force unlock expired lock
            _forceUnlock();
        }
        
        if (currentExecution.isLocked) {
            return false;
        }
        
        currentExecution = ExecutionInfo({
            isLocked: true,
            executor: msg.sender,
            lockTime: block.timestamp,
            status: ExecutionStatus.InProgress,
            failureReason: ""
        });
        
        emit ExecutionLocked(msg.sender, block.timestamp);
        return true;
    }

    /// @notice Unlock execution after completion
    function unlockExecution() external {
        require(
            currentExecution.executor == msg.sender || 
            block.timestamp > currentExecution.lockTime + LOCK_TIMEOUT,
            "Only executor or timeout can unlock"
        );
        
        _unlock();
    }

    /// @notice Record successful execution
    function recordSuccessfulExecution() external {
        require(currentExecution.executor == msg.sender, "Only executor can record");
        
        currentExecution.status = ExecutionStatus.Completed;
        lastSuccessfulExecution = block.timestamp;
        totalExecutions++;
        
        emit ExecutionCompleted(msg.sender, block.timestamp);
    }

    /// @notice Record failed execution
    /// @param reason Failure reason
    function recordFailedExecution(string memory reason) external {
        require(currentExecution.executor == msg.sender, "Only executor can record");
        
        currentExecution.status = ExecutionStatus.Failed;
        currentExecution.failureReason = reason;
        failedExecutions++;
        
        emit ExecutionFailed(msg.sender, reason);
    }

    /// @notice Check if execution is currently locked
    /// @return Whether execution is locked
    function isExecutionLocked() external view returns (bool) {
        if (!currentExecution.isLocked) {
            return false;
        }
        
        // Check if lock is expired
        if (block.timestamp > currentExecution.lockTime + LOCK_TIMEOUT) {
            return false;
        }
        
        return true;
    }

    /// @notice Get current execution status
    /// @return Current execution status
    function getExecutionStatus() external view returns (ExecutionStatus) {
        if (!currentExecution.isLocked) {
            return ExecutionStatus.Idle;
        }
        return currentExecution.status;
    }

    /// @notice Get execution statistics
    /// @return total Total executions
    /// @return failed Failed executions
    /// @return lastSuccess Timestamp of last successful execution
    function getExecutionStats() external view returns (
        uint256 total,
        uint256 failed,
        uint256 lastSuccess
    ) {
        return (totalExecutions, failedExecutions, lastSuccessfulExecution);
    }

    /// @notice Internal function to unlock
    function _unlock() private {
        address executor = currentExecution.executor;
        currentExecution.isLocked = false;
        currentExecution.executor = address(0);
        
        emit ExecutionUnlocked(executor, block.timestamp);
    }

    /// @notice Internal function to force unlock expired lock
    function _forceUnlock() private {
        _unlock();
    }
}