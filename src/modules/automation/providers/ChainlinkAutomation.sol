// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../../interfaces/IAutomation.sol";
import "../../../interfaces/ICycleManager.sol";
import "../../../interfaces/IDistributionModule.sol";
import "../AutomationManager.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title ChainlinkAutomation
/// @notice Chainlink Automation provider implementation
/// @dev Implements Chainlink Keeper compatible automation for yield distribution
contract ChainlinkAutomation is IAutomation, Initializable, OwnableUpgradeable {
    ICycleManager public cycleManager;
    IDistributionModule public distributionModule;
    AutomationManager public automationManager;
    
    bool public isActive;
    uint256 public lastUpkeepBlock;
    uint256 public minBlockInterval;

    event UpkeepPerformed(uint256 blockNumber, bytes performData);
    event CycleManagerUpdated(address indexed cycleManager);
    event DistributionModuleUpdated(address indexed distributionModule);
    event AutomationManagerUpdated(address indexed automationManager);
    event ProviderStatusChanged(bool isActive);

    error ZeroAddress();
    error UpkeepNotNeeded();
    error ExecutionFailed(string reason);
    error TooSoonToExecute();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _distributionModule,
        address _automationManager
    ) public initializer {
        __Ownable_init(_owner);
        
        if (_distributionModule == address(0) || _automationManager == address(0)) {
            revert ZeroAddress();
        }
        
        distributionModule = IDistributionModule(_distributionModule);
        automationManager = AutomationManager(_automationManager);
        isActive = true;
        minBlockInterval = 50; // Minimum blocks between upkeeps
    }

    /// @notice Chainlink-compatible upkeep check
    /// @return upkeepNeeded Whether upkeep is needed
    /// @return performData The data to pass to performUpkeep
    function checkUpkeep(bytes calldata) 
        external 
        view 
        returns (bool upkeepNeeded, bytes memory performData) 
    {
        return checkCondition();
    }

    /// @notice Checks if automation condition is met
    /// @return needsExecution Whether execution is needed
    /// @return performData The data for execution
    function checkCondition() public view override returns (bool needsExecution, bytes memory performData) {
        if (!isActive) {
            return (false, "Provider inactive");
        }

        if (block.number < lastUpkeepBlock + minBlockInterval) {
            return (false, "Too soon");
        }

        ExecutionCoordinator coordinator = automationManager.executionCoordinator();
        if (coordinator.isExecutionLocked()) {
            return (false, "Execution locked");
        }

        if (address(cycleManager) == address(0)) {
            return (false, "No cycle manager");
        }

        if (!cycleManager.isDistributionReady()) {
            return (false, "Distribution not ready");
        }

        return (true, abi.encodeWithSelector(this.performUpkeep.selector));
    }

    /// @notice Chainlink-compatible upkeep execution
    /// @param performData The data from checkUpkeep
    function performUpkeep(bytes calldata performData) external {
        execute(performData);
    }

    /// @notice Executes the automation task
    /// @param data The execution data
    function execute(bytes calldata data) public override {
        (bool upkeepNeeded, ) = checkCondition();
        if (!upkeepNeeded) {
            revert UpkeepNotNeeded();
        }

        lastUpkeepBlock = block.number;

        try automationManager.executeWithProvider(address(this), data) {
            emit UpkeepPerformed(block.number, data);
        } catch Error(string memory reason) {
            revert ExecutionFailed(reason);
        }
    }

    /// @notice Checks if the provider is active
    /// @return Whether the provider is active
    function isProviderActive() external view override returns (bool) {
        return isActive;
    }

    /// @notice Sets the cycle manager address
    /// @param _cycleManager The cycle manager address
    function setCycleManager(address _cycleManager) external override {
        if (msg.sender != owner() && msg.sender != address(automationManager)) {
            revert("Unauthorized");
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

    /// @notice Sets the provider active status
    /// @param _isActive Whether the provider should be active
    function setProviderStatus(bool _isActive) external onlyOwner {
        isActive = _isActive;
        emit ProviderStatusChanged(_isActive);
    }

    /// @notice Sets the minimum block interval between upkeeps
    /// @param _minBlockInterval The minimum number of blocks
    function setMinBlockInterval(uint256 _minBlockInterval) external onlyOwner {
        minBlockInterval = _minBlockInterval;
    }

    /// @notice Gets whether an upkeep is currently needed
    /// @return Whether upkeep is needed
    function getUpkeepNeeded() external view returns (bool) {
        (bool needed, ) = checkCondition();
        return needed;
    }
}