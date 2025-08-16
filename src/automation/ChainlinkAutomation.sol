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

/// @title ChainlinkAutomation
/// @notice Chainlink Automation implementation for yield distribution
/// @dev Implements Chainlink Automation compatible interface
contract ChainlinkAutomation is IAutomation {
    IDistributionModule public distributionModule;
    ICycleManager public cycleManager;
    address public automationManager;
    bool public isActive;
    address public owner;

    event UpkeepPerformed(uint256 timestamp, bytes performData);
    event CycleManagerUpdated(address indexed cycleManager);
    event DistributionModuleUpdated(address indexed distributionModule);
    event ProviderStatusChanged(bool isActive);

    error NotAuthorized();
    error ZeroAddress();
    error ExecutionLocked();
    error DistributionNotReady();

    modifier onlyAuthorized() {
        if (msg.sender != automationManager && msg.sender != owner) {
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

    /// @notice Check if upkeep is needed (Chainlink Automation interface)
    /// @return upkeepNeeded Whether upkeep is needed
    /// @return performData Data to pass to performUpkeep
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        return checkCondition();
    }

    /// @notice Perform upkeep (Chainlink Automation interface)
    /// @param performData Data from checkUpkeep
    function performUpkeep(bytes calldata performData) external {
        _execute(performData);
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

        if (!cycleManager.isDistributionReady()) {
            return (false, "Distribution not ready");
        }

        return (true, abi.encodeWithSelector(this.executeDistribution.selector));
    }

    /// @notice Execute the automation task
    /// @param data Encoded execution data from checkCondition
    function execute(bytes calldata data) external override {
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

        emit UpkeepPerformed(block.timestamp, data);
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

    /// @notice Get upkeep status for monitoring
    /// @return ready Whether upkeep is needed
    function getUpkeepNeeded() external view returns (bool ready) {
        (ready,) = checkCondition();
    }
}
