// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionStrategy} from "../../interfaces/IDistributionStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title BaseDistributionStrategy
/// @notice Abstract base contract for distribution strategies
/// @dev Provides common functionality for yield distribution strategies
abstract contract BaseDistributionStrategy is IDistributionStrategy, Ownable {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();

    IERC20 public immutable yieldToken;

    constructor(address _yieldToken) {
        if (_yieldToken == address(0)) revert ZeroAddress();
        yieldToken = IERC20(_yieldToken);
        _initializeOwner(msg.sender);
    }

    /// @inheritdoc IDistributionStrategy
    function distribute(uint256 amount) external virtual override {
        if (amount == 0) revert ZeroAmount();

        _distribute(amount);

        emit Distributed(amount);
    }

    /// @dev Internal distribution logic to be implemented by concrete strategies
    /// @param amount Amount to distribute
    function _distribute(uint256 amount) internal virtual;
}
