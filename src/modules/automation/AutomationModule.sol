// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../interfaces/ICycleManager.sol";
import "../../interfaces/IDistributionModule.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title AutomationModule
/// @notice Simple automation module that can be called by any automation provider
/// @dev Provides automation endpoints for Chainlink, Gelato, or any other automation service
contract AutomationModule is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    ICycleManager public cycleManager;
    IDistributionModule public distributionModule;

    uint256 public lastExecutionBlock;
    uint256 public minBlocksBetweenExecutions;
    bool public automationEnabled;

    mapping(address => bool) public authorizedCallers;

    event DistributionExecuted(address indexed executor, uint256 blockNumber);
    event AutomationStatusChanged(bool enabled);
    event CallerAuthorizationChanged(address indexed caller, bool authorized);
    event CycleManagerUpdated(address indexed cycleManager);
    event DistributionModuleUpdated(address indexed distributionModule);

    error NotAuthorized();
    error AutomationDisabled();
    error TooSoonToExecute();
    error DistributionNotReady();
    error ZeroAddress();

    modifier onlyAuthorized() {
        if (!authorizedCallers[msg.sender] && msg.sender != owner()) {
            revert NotAuthorized();
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

        automationEnabled = true;
        minBlocksBetweenExecutions = 50;
    }

    /// @notice Check if automation should execute (Chainlink compatible)
    /// @return upkeepNeeded Whether execution is needed
    /// @return performData The data to pass to performUpkeep
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        return _checkExecution();
    }

    /// @notice Execute automation (Chainlink compatible)
    /// @param performData The data from checkUpkeep
    function performUpkeep(bytes calldata performData) external nonReentrant onlyAuthorized {
        _executeDistribution();
    }

    /// @notice Check if automation should execute (Gelato compatible)
    /// @return canExec Whether execution is possible
    /// @return execPayload The execution payload
    function checker() external view returns (bool canExec, bytes memory execPayload) {
        return _checkExecution();
    }

    /// @notice Execute automation (Gelato compatible)
    /// @param execPayload The execution data
    function execute(bytes calldata execPayload) external nonReentrant onlyAuthorized {
        _executeDistribution();
    }

    /// @notice Generic automation execution endpoint
    function executeAutomation() external nonReentrant onlyAuthorized {
        _executeDistribution();
    }

    /// @notice Internal function to check if execution is needed
    function _checkExecution() internal view returns (bool needed, bytes memory data) {
        if (!automationEnabled) {
            return (false, "Automation disabled");
        }

        if (lastExecutionBlock > 0 && block.number < lastExecutionBlock + minBlocksBetweenExecutions) {
            return (false, "Too soon");
        }

        if (address(cycleManager) == address(0) || !cycleManager.isDistributionReady()) {
            return (false, "Distribution not ready");
        }

        return (true, abi.encodeWithSelector(this.executeAutomation.selector));
    }

    /// @notice Internal function to execute distribution
    function _executeDistribution() internal {
        if (!automationEnabled) revert AutomationDisabled();
        if (lastExecutionBlock > 0 && block.number < lastExecutionBlock + minBlocksBetweenExecutions) {
            revert TooSoonToExecute();
        }
        if (!cycleManager.isDistributionReady()) revert DistributionNotReady();

        lastExecutionBlock = block.number;

        distributionModule.distribute();
        cycleManager.startNewCycle();

        emit DistributionExecuted(msg.sender, block.number);
    }

    /// @notice Set authorization for a caller
    /// @param caller The address to authorize/unauthorize
    /// @param authorized Whether the caller should be authorized
    function setCallerAuthorization(address caller, bool authorized) external onlyOwner {
        authorizedCallers[caller] = authorized;
        emit CallerAuthorizationChanged(caller, authorized);
    }

    /// @notice Enable or disable automation
    /// @param enabled Whether automation should be enabled
    function setAutomationEnabled(bool enabled) external onlyOwner {
        automationEnabled = enabled;
        emit AutomationStatusChanged(enabled);
    }

    /// @notice Set the minimum blocks between executions
    /// @param blocks The minimum number of blocks
    function setMinBlocksBetweenExecutions(uint256 blocks) external onlyOwner {
        minBlocksBetweenExecutions = blocks;
    }

    /// @notice Set the cycle manager
    /// @param _cycleManager The cycle manager address
    function setCycleManager(address _cycleManager) external onlyOwner {
        if (_cycleManager == address(0)) revert ZeroAddress();
        cycleManager = ICycleManager(_cycleManager);
        emit CycleManagerUpdated(_cycleManager);
    }

    /// @notice Set the distribution module
    /// @param _distributionModule The distribution module address
    function setDistributionModule(address _distributionModule) external onlyOwner {
        if (_distributionModule == address(0)) revert ZeroAddress();
        distributionModule = IDistributionModule(_distributionModule);
        emit DistributionModuleUpdated(_distributionModule);
    }

    /// @notice Emergency execution by owner
    function emergencyExecute() external onlyOwner nonReentrant {
        if (!cycleManager.isDistributionReady()) revert DistributionNotReady();

        distributionModule.distribute();
        cycleManager.startNewCycle();

        emit DistributionExecuted(msg.sender, block.number);
    }
}
