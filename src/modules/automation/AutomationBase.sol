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

    /// @notice Resolves whether distribution should occur
    /// @dev Checks all conditions via CycleManager
    /// @return canExec Whether execution should proceed
    /// @return execPayload The encoded function call data
    function resolveDistribution() public view virtual returns (bool canExec, bytes memory execPayload) {
        return cycleManager.resolveDistribution();
    }

    /// @notice Executes the distribution
    /// @dev Calls CycleManager to handle all distribution logic
    function executeDistribution() public virtual {
        (bool resolved,) = resolveDistribution();
        if (!resolved) revert NotResolved();

        cycleManager.executeDistribution();

        emit AutomationExecuted(msg.sender, block.number);
    }
}
