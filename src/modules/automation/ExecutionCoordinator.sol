// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ExecutionCoordinator
/// @notice Coordinates execution between multiple automation providers to prevent conflicts
/// @dev Ensures only one provider can execute at a time and tracks execution history
contract ExecutionCoordinator {
    enum ExecutionStatus {
        Idle,
        Locked,
        Executed,
        Failed
    }

    struct ExecutionRecord {
        address provider;
        uint256 timestamp;
        uint256 blockNumber;
        ExecutionStatus status;
        string reason;
    }

    mapping(uint256 => bool) public executionLocks;
    mapping(uint256 => ExecutionRecord) public executionHistory;
    uint256 public lastExecutionId;
    uint256 public currentExecutionId;
    bool public globalExecutionLock;

    event ExecutionLocked(uint256 indexed executionId, address indexed provider);
    event ExecutionUnlocked(uint256 indexed executionId);
    event ExecutionRecorded(uint256 indexed executionId, ExecutionStatus status);

    error ExecutionAlreadyLocked();
    error ExecutionNotLocked();
    error UnauthorizedUnlock();

    /// @notice Attempts to acquire an execution lock
    /// @return success Whether the lock was successfully acquired
    function lockExecution() external returns (bool success) {
        if (globalExecutionLock) {
            return false;
        }

        globalExecutionLock = true;
        currentExecutionId++;
        executionLocks[currentExecutionId] = true;
        
        executionHistory[currentExecutionId] = ExecutionRecord({
            provider: msg.sender,
            timestamp: block.timestamp,
            blockNumber: block.number,
            status: ExecutionStatus.Locked,
            reason: ""
        });

        emit ExecutionLocked(currentExecutionId, msg.sender);
        return true;
    }

    /// @notice Releases the execution lock
    function unlockExecution() external {
        if (!globalExecutionLock) {
            revert ExecutionNotLocked();
        }
        
        if (executionHistory[currentExecutionId].provider != msg.sender) {
            revert UnauthorizedUnlock();
        }

        globalExecutionLock = false;
        executionLocks[currentExecutionId] = false;
        lastExecutionId = currentExecutionId;

        emit ExecutionUnlocked(currentExecutionId);
    }

    /// @notice Checks if execution is currently locked
    /// @return Whether execution is locked
    function isExecutionLocked() external view returns (bool) {
        return globalExecutionLock;
    }

    /// @notice Records a successful execution
    function recordSuccessfulExecution() external {
        if (executionHistory[currentExecutionId].provider != msg.sender) {
            revert UnauthorizedUnlock();
        }

        executionHistory[currentExecutionId].status = ExecutionStatus.Executed;
        emit ExecutionRecorded(currentExecutionId, ExecutionStatus.Executed);
    }

    /// @notice Records a failed execution
    /// @param reason The reason for failure
    function recordFailedExecution(string memory reason) external {
        if (executionHistory[currentExecutionId].provider != msg.sender) {
            revert UnauthorizedUnlock();
        }

        executionHistory[currentExecutionId].status = ExecutionStatus.Failed;
        executionHistory[currentExecutionId].reason = reason;
        emit ExecutionRecorded(currentExecutionId, ExecutionStatus.Failed);
    }

    /// @notice Gets the current execution status
    /// @return status The current execution status
    function getExecutionStatus() external view returns (ExecutionStatus status) {
        if (globalExecutionLock) {
            return ExecutionStatus.Locked;
        }
        if (lastExecutionId > 0) {
            return executionHistory[lastExecutionId].status;
        }
        return ExecutionStatus.Idle;
    }

    /// @notice Gets execution history for a specific ID
    /// @param executionId The execution ID to query
    /// @return record The execution record
    function getExecutionRecord(uint256 executionId) external view returns (ExecutionRecord memory record) {
        return executionHistory[executionId];
    }
}