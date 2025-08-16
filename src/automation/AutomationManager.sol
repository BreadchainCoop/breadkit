// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IAutomation.sol";
import "./ExecutionCoordinator.sol";

interface ICycleManager {
    function isDistributionReady() external view returns (bool);
    function getBlocksUntilNextCycle() external view returns (uint256);
    function startNewCycle() external;
    function getCycleInfo() external view returns (uint256 cycleNumber, uint256 startBlock, uint256 endBlock);
}

/// @title AutomationManager
/// @notice Manages multiple automation providers for redundant execution
/// @dev Coordinates execution between different automation networks while preventing double-execution
contract AutomationManager {
    struct Provider {
        string name;
        uint256 priority;
        bool isActive;
        bool isRegistered;
        uint256 executionCount;
        uint256 lastExecution;
    }

    mapping(address => Provider) public providers;
    address[] public providerList;
    address public primaryProvider;
    ICycleManager public cycleManager;
    ExecutionCoordinator public executionCoordinator;
    address public owner;

    event ProviderRegistered(address indexed provider, string name, uint256 priority);
    event ProviderStatusChanged(address indexed provider, bool isActive);
    event CycleManagerUpdated(address indexed cycleManager);
    event AutomationExecuted(address indexed provider, uint256 timestamp);
    event ExecutionFailed(address indexed provider, string reason);

    error ZeroAddress();
    error NotOwner();
    error ProviderAlreadyRegistered();
    error ProviderNotRegistered();
    error ExecutionLocked();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyRegisteredProvider() {
        if (!providers[msg.sender].isRegistered) revert ProviderNotRegistered();
        _;
    }

    constructor() {
        owner = msg.sender;
        executionCoordinator = new ExecutionCoordinator();
    }

    /// @notice Register a new automation provider
    /// @param provider Address of the automation provider contract
    /// @param name Name identifier for the provider
    /// @param priority Execution priority (lower number = higher priority)
    function registerProvider(
        address provider,
        string calldata name,
        uint256 priority
    ) external onlyOwner {
        if (provider == address(0)) revert ZeroAddress();
        if (providers[provider].isRegistered) revert ProviderAlreadyRegistered();
        
        providers[provider] = Provider({
            name: name,
            priority: priority,
            isActive: true,
            isRegistered: true,
            executionCount: 0,
            lastExecution: 0
        });
        
        providerList.push(provider);
        
        if (address(cycleManager) != address(0)) {
            IAutomation(provider).setCycleManager(address(cycleManager));
        }
        
        emit ProviderRegistered(provider, name, priority);
    }

    /// @notice Enable or disable a provider
    /// @param provider Address of the provider
    /// @param enabled Whether to enable or disable the provider
    function setProviderStatus(address provider, bool enabled) external onlyOwner {
        if (!providers[provider].isRegistered) revert ProviderNotRegistered();
        providers[provider].isActive = enabled;
        emit ProviderStatusChanged(provider, enabled);
    }

    /// @notice Set the cycle manager for all providers
    /// @param _cycleManager Address of the cycle manager
    function setCycleManager(address _cycleManager) external onlyOwner {
        if (_cycleManager == address(0)) revert ZeroAddress();
        cycleManager = ICycleManager(_cycleManager);
        
        for (uint256 i = 0; i < providerList.length; i++) {
            if (providers[providerList[i]].isRegistered) {
                IAutomation(providerList[i]).setCycleManager(_cycleManager);
            }
        }
        
        emit CycleManagerUpdated(_cycleManager);
    }

    /// @notice Check if automation execution is needed
    /// @return needsExecution Whether execution is needed
    /// @return executionData Data to pass to execution function
    function checkExecution() external view returns (bool needsExecution, bytes memory executionData) {
        if (executionCoordinator.isExecutionLocked()) {
            return (false, "Execution locked");
        }
        
        if (address(cycleManager) == address(0) || !cycleManager.isDistributionReady()) {
            return (false, "Distribution not ready");
        }
        
        return (true, abi.encodeWithSelector(this.executeWithProvider.selector, msg.sender));
    }

    /// @notice Execute automation through a specific provider
    /// @param provider Address of the provider executing
    /// @param data Execution data
    function executeWithProvider(address provider, bytes calldata data) external onlyRegisteredProvider {
        if (!providers[provider].isActive) revert ProviderNotRegistered();
        if (!executionCoordinator.lockExecution()) revert ExecutionLocked();
        
        try IAutomation(provider).execute(data) {
            providers[provider].executionCount++;
            providers[provider].lastExecution = block.timestamp;
            executionCoordinator.recordSuccessfulExecution();
            emit AutomationExecuted(provider, block.timestamp);
        } catch Error(string memory reason) {
            executionCoordinator.recordFailedExecution(reason);
            emit ExecutionFailed(provider, reason);
            revert(reason);
        }
        
        executionCoordinator.unlockExecution();
    }

    /// @notice Get the next distribution time
    /// @return Blocks until next distribution
    function getNextDistributionTime() external view returns (uint256) {
        if (address(cycleManager) == address(0)) return 0;
        return cycleManager.getBlocksUntilNextCycle();
    }

    /// @notice Get provider information
    /// @param provider Address of the provider
    /// @return Provider information struct
    function getProvider(address provider) external view returns (Provider memory) {
        return providers[provider];
    }

    /// @notice Get all registered providers
    /// @return Array of provider addresses
    function getProviders() external view returns (address[] memory) {
        return providerList;
    }
}