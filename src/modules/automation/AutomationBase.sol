// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../interfaces/ICycleManager.sol";
import "../../interfaces/IDistributionManager.sol";

/// @title AutomationBase
/// @notice Abstract base contract for automation providers
/// @dev Inherit this contract to create provider-specific automation implementations
abstract contract AutomationBase is IDistributionManager {
    ICycleManager public immutable cycleManager;
    IDistributionManager public immutable distributionManager;

    event AutomationExecuted(address indexed executor, uint256 blockNumber);

    error NotResolved();

    constructor(address _cycleManager, address _distributionManager) {
        require(_cycleManager != address(0), "Invalid cycle manager");
        require(_distributionManager != address(0), "Invalid distribution manager");
        cycleManager = ICycleManager(_cycleManager);
        distributionManager = IDistributionManager(_distributionManager);
    }

    /// @notice Checks if distribution is ready
    /// @dev Delegates to DistributionManager for condition checking
    /// @return ready Whether the distribution conditions are met
    function isDistributionReady() public view virtual override returns (bool ready) {
        return distributionManager.isDistributionReady();
    }

    /// @notice Gets the automation data for execution
    /// @dev Delegates to CycleManager for payload generation
    /// @return execPayload The encoded function call data
    function getAutomationData() public view virtual returns (bytes memory execPayload) {
        return cycleManager.getAutomationData();
    }

    /// @notice Executes the distribution
    /// @dev Delegates to DistributionManager for execution
    function executeDistribution() public virtual override {
        if (!isDistributionReady()) revert NotResolved();

        distributionManager.executeDistribution();

        emit AutomationExecuted(msg.sender, block.number);
    }
}
