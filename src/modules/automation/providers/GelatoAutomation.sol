// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../../interfaces/IAutomation.sol";
import "../../../interfaces/ICycleManager.sol";
import "../../../interfaces/IDistributionModule.sol";
import "../AutomationManager.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title GelatoAutomation
/// @notice Gelato Network automation provider implementation
/// @dev Implements Gelato-compatible automation for yield distribution
contract GelatoAutomation is IAutomation, Initializable, OwnableUpgradeable {
    ICycleManager public cycleManager;
    IDistributionModule public distributionModule;
    AutomationManager public automationManager;
    
    bytes32 public taskId;
    address public gelatoExecutor;
    bool public isActive;
    uint256 public lastExecutionBlock;
    uint256 public minBlockInterval;

    event TaskExecuted(bytes32 indexed taskId, uint256 blockNumber);
    event TaskCreated(bytes32 indexed taskId);
    event TaskCancelled(bytes32 indexed taskId);
    event CycleManagerUpdated(address indexed cycleManager);
    event DistributionModuleUpdated(address indexed distributionModule);
    event AutomationManagerUpdated(address indexed automationManager);
    event GelatoExecutorUpdated(address indexed executor);
    event ProviderStatusChanged(bool isActive);

    error ZeroAddress();
    error ExecutionNotNeeded();
    error ExecutionFailed(string reason);
    error UnauthorizedExecutor();
    error TooSoonToExecute();

    modifier onlyGelatoExecutor() {
        if (msg.sender != gelatoExecutor && msg.sender != owner()) {
            revert UnauthorizedExecutor();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _distributionModule,
        address _automationManager,
        address _gelatoExecutor
    ) public initializer {
        __Ownable_init(_owner);
        
        if (_distributionModule == address(0) || _automationManager == address(0)) {
            revert ZeroAddress();
        }
        
        distributionModule = IDistributionModule(_distributionModule);
        automationManager = AutomationManager(_automationManager);
        gelatoExecutor = _gelatoExecutor;
        isActive = true;
        minBlockInterval = 50; // Minimum blocks between executions
    }

    /// @notice Gelato-compatible checker function
    /// @return canExec Whether execution is possible
    /// @return execPayload The execution payload
    function checker() external view returns (bool canExec, bytes memory execPayload) {
        return checkCondition();
    }

    /// @notice Checks if automation condition is met
    /// @return needsExecution Whether execution is needed
    /// @return performData The data for execution
    function checkCondition() public view override returns (bool needsExecution, bytes memory performData) {
        if (!isActive) {
            return (false, bytes("Provider inactive"));
        }

        if (block.number < lastExecutionBlock + minBlockInterval) {
            return (false, bytes("Too soon"));
        }

        ExecutionCoordinator coordinator = automationManager.executionCoordinator();
        if (coordinator.isExecutionLocked()) {
            return (false, bytes("Execution locked"));
        }

        if (address(cycleManager) == address(0)) {
            return (false, bytes("No cycle manager"));
        }

        if (cycleManager.getBlocksUntilNextCycle() > 0) {
            return (false, bytes("Cycle not complete"));
        }

        if (!cycleManager.isDistributionReady()) {
            return (false, bytes("Distribution not ready"));
        }

        return (true, abi.encodeWithSelector(this.execCall.selector));
    }

    /// @notice Gelato-compatible execution function
    /// @param data The execution data
    function execCall(bytes calldata data) external onlyGelatoExecutor {
        execute(data);
    }

    /// @notice Executes the automation task
    /// @param data The execution data
    function execute(bytes calldata data) public override {
        (bool canExec, ) = checkCondition();
        if (!canExec) {
            revert ExecutionNotNeeded();
        }

        lastExecutionBlock = block.number;

        try automationManager.executeWithProvider(address(this), data) {
            emit TaskExecuted(taskId, block.number);
        } catch Error(string memory reason) {
            revert ExecutionFailed(reason);
        }
    }

    /// @notice Creates a new Gelato task
    /// @return newTaskId The ID of the created task
    function createTask() external onlyOwner returns (bytes32 newTaskId) {
        // Generate a unique task ID based on contract address and current block
        newTaskId = keccak256(abi.encodePacked(address(this), block.number, block.timestamp));
        taskId = newTaskId;
        
        emit TaskCreated(newTaskId);
        return newTaskId;
    }

    /// @notice Cancels the current Gelato task
    function cancelTask() external onlyOwner {
        bytes32 currentTaskId = taskId;
        taskId = bytes32(0);
        
        emit TaskCancelled(currentTaskId);
    }

    /// @notice Gets the current task ID
    /// @return The current task ID
    function getTaskId() external view returns (bytes32) {
        return taskId;
    }

    /// @notice Checks if the provider is active
    /// @return Whether the provider is active
    function isProviderActive() external view override returns (bool) {
        return isActive && taskId != bytes32(0);
    }

    /// @notice Sets the cycle manager address
    /// @param _cycleManager The cycle manager address
    function setCycleManager(address _cycleManager) external override {
        if (msg.sender != owner() && msg.sender != address(automationManager)) {
            revert UnauthorizedExecutor();
        }
        if (_cycleManager == address(0)) revert ZeroAddress();
        
        cycleManager = ICycleManager(_cycleManager);
        emit CycleManagerUpdated(_cycleManager);
    }

    /// @notice Gets the cycle manager address
    /// @return The cycle manager address
    function getCycleManager() external view override returns (address) {
        return address(cycleManager);
    }

    /// @notice Sets the distribution module address
    /// @param _distributionModule The distribution module address
    function setDistributionModule(address _distributionModule) external onlyOwner {
        if (_distributionModule == address(0)) revert ZeroAddress();
        
        distributionModule = IDistributionModule(_distributionModule);
        emit DistributionModuleUpdated(_distributionModule);
    }

    /// @notice Sets the automation manager address
    /// @param _automationManager The automation manager address
    function setAutomationManager(address _automationManager) external onlyOwner {
        if (_automationManager == address(0)) revert ZeroAddress();
        
        automationManager = AutomationManager(_automationManager);
        emit AutomationManagerUpdated(_automationManager);
    }

    /// @notice Sets the Gelato executor address
    /// @param _gelatoExecutor The executor address
    function setGelatoExecutor(address _gelatoExecutor) external onlyOwner {
        if (_gelatoExecutor == address(0)) revert ZeroAddress();
        
        gelatoExecutor = _gelatoExecutor;
        emit GelatoExecutorUpdated(_gelatoExecutor);
    }

    /// @notice Sets the provider active status
    /// @param _isActive Whether the provider should be active
    function setProviderStatus(bool _isActive) external onlyOwner {
        isActive = _isActive;
        emit ProviderStatusChanged(_isActive);
    }

    /// @notice Sets the minimum block interval between executions
    /// @param _minBlockInterval The minimum number of blocks
    function setMinBlockInterval(uint256 _minBlockInterval) external onlyOwner {
        minBlockInterval = _minBlockInterval;
    }

    /// @notice Checks if execution is currently needed
    /// @return Whether execution is needed
    function isExecutionNeeded() external view returns (bool) {
        (bool needed, ) = checkCondition();
        return needed;
    }
}