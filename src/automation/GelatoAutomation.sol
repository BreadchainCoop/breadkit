// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IAutomation.sol";
import "../interfaces/IDistributionModule.sol";

interface ICycleManager {
    function isDistributionReady() external view returns (bool);
    function getBlocksUntilNextCycle() external view returns (uint256);
    function startNewCycle() external;
    function getCycleInfo() external view returns (uint256 cycleNumber, uint256 startBlock, uint256 endBlock);
}

/// @title GelatoAutomation
/// @notice Gelato Network automation implementation for yield distribution
/// @dev Implements Gelato automation compatible interface
contract GelatoAutomation is IAutomation {
    IDistributionModule public distributionModule;
    ICycleManager public cycleManager;
    address public automationManager;
    bytes32 public taskId;
    bool public isActive;
    address public owner;

    // Gelato specific
    address public dedicatedMsgSender;
    address public constant GELATO_AUTOMATE = 0x527a819db1eb0e34426297b03bae11F2f8B3A19E; // Gnosis Chain

    event TaskExecuted(uint256 timestamp, bytes execData);
    event TaskCreated(bytes32 indexed taskId);
    event TaskCancelled(bytes32 indexed taskId);
    event CycleManagerUpdated(address indexed cycleManager);
    event DistributionModuleUpdated(address indexed distributionModule);
    event ProviderStatusChanged(bool isActive);

    error NotAuthorized();
    error ZeroAddress();
    error ExecutionLocked();
    error DistributionNotReady();

    modifier onlyAuthorized() {
        if (
            msg.sender != automationManager && msg.sender != owner && msg.sender != dedicatedMsgSender
                && msg.sender != GELATO_AUTOMATE
        ) {
            revert NotAuthorized();
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAuthorized();
        _;
    }

    constructor(address _automationManager, address _distributionModule) {
        if (_automationManager == address(0) || _distributionModule == address(0)) {
            revert ZeroAddress();
        }
        automationManager = _automationManager;
        distributionModule = IDistributionModule(_distributionModule);
        owner = msg.sender;
        isActive = true;
    }

    /// @notice Gelato checker function to determine if execution is needed
    /// @return canExec Whether execution is needed
    /// @return execPayload Encoded execution data
    function checker() external view returns (bool canExec, bytes memory execPayload) {
        return checkCondition();
    }

    /// @notice Gelato execution function
    /// @param execData Execution data from checker
    function execCall(bytes calldata execData) external onlyAuthorized {
        _execute(execData);
    }

    /// @notice Check if automation execution condition is met
    /// @return canExecute Whether the condition is met
    /// @return executionData Encoded data to pass to execute function
    function checkCondition() public view override returns (bool canExecute, bytes memory executionData) {
        if (!isActive) {
            return (false, "Provider not active");
        }

        if (address(cycleManager) == address(0)) {
            return (false, "Cycle manager not set");
        }

        // Check if enough blocks have passed
        if (cycleManager.getBlocksUntilNextCycle() > 0) {
            return (false, "Cycle not complete");
        }

        // Check if distribution is ready
        if (!cycleManager.isDistributionReady()) {
            return (false, "Distribution conditions not met");
        }

        return (true, abi.encodeWithSelector(this.executeDistribution.selector));
    }

    /// @notice Execute the automation task
    /// @param data Encoded execution data from checkCondition
    function execute(bytes calldata data) external override onlyAuthorized {
        _execute(data);
    }

    /// @notice Internal execute implementation
    /// @param data Encoded execution data
    function _execute(bytes calldata data) internal {
        if (!isActive) revert NotAuthorized();

        (bool canExecute,) = checkCondition();
        if (!canExecute) revert DistributionNotReady();

        // Decode and execute the function call
        (bool success,) = address(this).call(data);
        require(success, "Execution failed");

        emit TaskExecuted(block.timestamp, data);
    }

    /// @notice Execute distribution through distribution module
    function executeDistribution() external onlyAuthorized {
        if (!cycleManager.isDistributionReady()) {
            revert DistributionNotReady();
        }

        // Trigger distribution
        distributionModule.distribute();

        // Start new cycle
        cycleManager.startNewCycle();
    }

    /// @notice Check if the provider is currently active
    /// @return Whether the provider is active and ready
    function isProviderActive() external view override returns (bool) {
        return isActive;
    }

    /// @notice Set the cycle manager address
    /// @param _cycleManager Address of the cycle manager contract
    function setCycleManager(address _cycleManager) external override onlyAuthorized {
        if (_cycleManager == address(0)) revert ZeroAddress();
        cycleManager = ICycleManager(_cycleManager);
        emit CycleManagerUpdated(_cycleManager);
    }

    /// @notice Set the distribution module address
    /// @param _distributionModule Address of the distribution module contract
    function setDistributionModule(address _distributionModule) external onlyOwner {
        if (_distributionModule == address(0)) revert ZeroAddress();
        distributionModule = IDistributionModule(_distributionModule);
        emit DistributionModuleUpdated(_distributionModule);
    }

    /// @notice Set provider active status
    /// @param _isActive Whether the provider should be active
    function setActive(bool _isActive) external onlyOwner {
        isActive = _isActive;
        emit ProviderStatusChanged(_isActive);
    }

    /// @notice Create a Gelato task for automation
    function createTask() external onlyOwner {
        // In production, this would interact with Gelato's task creation
        // For now, we generate a mock task ID
        taskId = keccak256(abi.encodePacked(address(this), block.timestamp));
        emit TaskCreated(taskId);
    }

    /// @notice Cancel the Gelato task
    function cancelTask() external onlyOwner {
        bytes32 _taskId = taskId;
        taskId = bytes32(0);
        emit TaskCancelled(_taskId);
    }

    /// @notice Get the current task ID
    /// @return Current task ID
    function getTaskId() external view returns (bytes32) {
        return taskId;
    }

    /// @notice Set dedicated message sender for Gelato
    /// @param _dedicatedMsgSender Address of dedicated sender
    function setDedicatedMsgSender(address _dedicatedMsgSender) external onlyOwner {
        dedicatedMsgSender = _dedicatedMsgSender;
    }
}
