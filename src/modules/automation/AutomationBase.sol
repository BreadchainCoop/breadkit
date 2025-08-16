// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../interfaces/IDistributionManager.sol";

/// @title AutomationBase
/// @notice Abstract base contract for automation providers
/// @dev Inherit this contract to create provider-specific automation implementations
abstract contract AutomationBase is IDistributionManager {
    IDistributionManager public immutable distributionManager;

    event AutomationExecuted(address indexed executor, uint256 blockNumber);

    error NotResolved();

    constructor(address _distributionManager) {
        require(_distributionManager != address(0), "Invalid distribution manager");
        distributionManager = IDistributionManager(_distributionManager);
    }

    /// @notice Checks if distribution is ready
    /// @dev Delegates to DistributionManager for condition checking
    /// @return ready Whether the distribution conditions are met
    function isDistributionReady() public view virtual override returns (bool ready) {
        return distributionManager.isDistributionReady();
    }

    /// @notice Gets the automation data for execution
    /// @dev Returns encoded function call data for automation providers
    /// @return execPayload The encoded function call data
    function getAutomationData() public view virtual returns (bytes memory execPayload) {
        // Default implementation: return encoded call to executeDistribution
        if (isDistributionReady()) {
            return abi.encodeWithSelector(this.executeDistribution.selector);
        }
        return new bytes(0);
    }

    /// @notice Executes the distribution
    /// @dev Delegates to DistributionManager for execution
    function executeDistribution() public virtual override {
        if (!isDistributionReady()) revert NotResolved();

        distributionManager.executeDistribution();

        emit AutomationExecuted(msg.sender, block.number);
    }
}
