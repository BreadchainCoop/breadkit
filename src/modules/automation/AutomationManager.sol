// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../interfaces/IAutomation.sol";
import "../../interfaces/ICycleManager.sol";
import "../../interfaces/IDistributionModule.sol";
import "./ExecutionCoordinator.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title AutomationManager
/// @notice Manages multiple automation providers for protocol operations
/// @dev Coordinates between different automation networks to ensure reliable execution
contract AutomationManager is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
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
    IDistributionModule public distributionModule;
    ExecutionCoordinator public executionCoordinator;

    event ProviderRegistered(address indexed provider, string name, uint256 priority);
    event ProviderStatusChanged(address indexed provider, bool isActive);
    event PrimaryProviderSet(address indexed provider);
    event CycleManagerUpdated(address indexed cycleManager);
    event DistributionModuleUpdated(address indexed distributionModule);
    event AutomationExecuted(address indexed provider, uint256 timestamp);
    event ExecutionFailed(address indexed provider, string reason);

    error ZeroAddress();
    error ProviderNotRegistered();
    error ProviderAlreadyRegistered();
    error ExecutionLocked();
    error InvalidProvider();
    error DistributionNotReady();

    modifier onlyAutomatedCaller() {
        if (!providers[msg.sender].isRegistered || !providers[msg.sender].isActive) {
            revert InvalidProvider();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        executionCoordinator = new ExecutionCoordinator();
    }

    /// @notice Registers a new automation provider
    /// @param provider The address of the automation provider
    /// @param name The name of the provider
    /// @param priority The priority level (lower number = higher priority)
    function registerProvider(address provider, string calldata name, uint256 priority) external onlyOwner {
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

    /// @notice Sets the active status of a provider
    /// @param provider The address of the provider
    /// @param isActive Whether the provider should be active
    function setProviderStatus(address provider, bool isActive) external onlyOwner {
        if (!providers[provider].isRegistered) revert ProviderNotRegistered();

        providers[provider].isActive = isActive;
        emit ProviderStatusChanged(provider, isActive);
    }

    /// @notice Sets the primary automation provider
    /// @param provider The address of the provider to set as primary
    function setPrimaryProvider(address provider) external onlyOwner {
        if (!providers[provider].isRegistered) revert ProviderNotRegistered();

        primaryProvider = provider;
        emit PrimaryProviderSet(provider);
    }

    /// @notice Sets the cycle manager for all providers
    /// @param _cycleManager The address of the cycle manager
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

    /// @notice Sets the distribution module
    /// @param _distributionModule The address of the distribution module
    function setDistributionModule(address _distributionModule) external onlyOwner {
        if (_distributionModule == address(0)) revert ZeroAddress();
        distributionModule = IDistributionModule(_distributionModule);
        emit DistributionModuleUpdated(_distributionModule);
    }

    /// @notice Checks if execution is needed and returns execution data
    /// @return upkeepNeeded Whether execution is needed
    /// @return performData The data to pass to the execution function
    function checkExecution() external view returns (bool upkeepNeeded, bytes memory performData) {
        if (executionCoordinator.isExecutionLocked()) {
            return (false, "Execution locked");
        }

        if (address(cycleManager) == address(0) || !cycleManager.isDistributionReady()) {
            return (false, "Distribution not ready");
        }

        return (true, abi.encodeWithSelector(this.executeDistribution.selector));
    }

    /// @notice Executes distribution through a specific provider
    /// @param provider The provider executing the distribution
    /// @param data The execution data
    function executeWithProvider(address provider, bytes calldata data) external onlyAutomatedCaller nonReentrant {
        if (provider != msg.sender) revert InvalidProvider();

        _executeDistribution();
    }

    /// @notice Main distribution execution function
    function executeDistribution() external onlyAutomatedCaller nonReentrant {
        _executeDistribution();
    }

    /// @notice Internal function to execute distribution
    function _executeDistribution() internal {
        if (!executionCoordinator.lockExecution()) {
            revert ExecutionLocked();
        }

        try distributionModule.distribute() {
            providers[msg.sender].executionCount++;
            providers[msg.sender].lastExecution = block.timestamp;

            cycleManager.startNewCycle();
            executionCoordinator.recordSuccessfulExecution();

            emit AutomationExecuted(msg.sender, block.timestamp);
        } catch Error(string memory reason) {
            executionCoordinator.recordFailedExecution(reason);
            emit ExecutionFailed(msg.sender, reason);
        } catch {
            executionCoordinator.recordFailedExecution("Unknown error");
            emit ExecutionFailed(msg.sender, "Unknown error");
        }

        executionCoordinator.unlockExecution();
    }

    /// @notice Gets the next distribution time from the cycle manager
    /// @return blocks The number of blocks until the next distribution
    function getNextDistributionTime() external view returns (uint256 blocks) {
        if (address(cycleManager) == address(0)) {
            return 0;
        }
        return cycleManager.getBlocksUntilNextCycle();
    }

    /// @notice Gets information about a specific provider
    /// @param provider The address of the provider
    /// @return name The provider's name
    /// @return priority The provider's priority
    /// @return isActive Whether the provider is active
    /// @return executionCount Number of successful executions
    /// @return lastExecution Timestamp of last execution
    function getProviderInfo(address provider)
        external
        view
        returns (string memory name, uint256 priority, bool isActive, uint256 executionCount, uint256 lastExecution)
    {
        Provider memory p = providers[provider];
        return (p.name, p.priority, p.isActive, p.executionCount, p.lastExecution);
    }

    /// @notice Gets the list of all registered providers
    /// @return The array of provider addresses
    function getProviderList() external view returns (address[] memory) {
        return providerList;
    }

    /// @notice Emergency function to manually execute distribution
    /// @dev Only owner can call this in case automation fails
    function emergencyExecute() external onlyOwner nonReentrant {
        if (!cycleManager.isDistributionReady()) {
            revert DistributionNotReady();
        }

        distributionModule.distribute();
        cycleManager.startNewCycle();

        emit AutomationExecuted(address(this), block.timestamp);
    }
}
