// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./abstracts/AbstractCycleModule.sol";

/// @title CycleModule
/// @notice Concrete implementation of the cycle module
/// @dev Extends AbstractCycleModule with any protocol-specific logic
contract CycleModule is AbstractCycleModule {
    /// @notice Constructor only sets up authorization (via parent constructor)
    constructor() AbstractCycleModule() {}
}
