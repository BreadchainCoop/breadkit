// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./abstracts/AbstractCycleModule.sol";

/// @title CycleModule
/// @notice Concrete implementation of the cycle module
/// @dev Extends AbstractCycleModule with any protocol-specific logic
contract CycleModule is AbstractCycleModule {
    /// @notice Constructor only sets up authorization (via parent constructor)
    constructor() AbstractCycleModule() {}

    /// @notice Override to add custom validation logic if needed
    /// @dev This example allows any valid cycle transition
    /// @return Always returns true in this basic implementation
    function _validateCycleTransition() internal pure override returns (bool) {
        // Additional custom validation can be added here
        // For example: checking if certain conditions are met
        // return someCustomCondition();

        return true;
    }
}
