// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../interfaces/ICycleManager.sol";

/// @title AutomationBase
/// @notice Abstract base contract for automation providers
/// @dev Inherit this contract to create provider-specific automation implementations
abstract contract AutomationBase {
    ICycleManager public immutable cycleManager;

    event AutomationExecuted(address indexed executor, uint256 blockNumber);

    error NotResolved();

    constructor(address _cycleManager) {
        require(_cycleManager != address(0), "Invalid cycle manager");
        cycleManager = ICycleManager(_cycleManager);
    }

    /// @notice Checks if distribution is ready
    /// @dev Delegates to CycleManager for condition checking
    /// @return ready Whether the distribution conditions are met
    function isDistributionReady() public view virtual returns (bool ready) {
        return cycleManager.isDistributionReady();
    }

    /// @notice Gets the automation data for execution
    /// @dev Delegates to CycleManager for payload generation
    /// @return execPayload The encoded function call data
    function getAutomationData() public view virtual returns (bytes memory execPayload) {
        return cycleManager.getAutomationData();
    }

    /// @notice Executes the distribution
    /// @dev Calls CycleManager to handle all distribution logic
    function executeDistribution() public virtual {
        if (!isDistributionReady()) revert NotResolved();

        cycleManager.executeDistribution();

        emit AutomationExecuted(msg.sender, block.number);
    }
}
