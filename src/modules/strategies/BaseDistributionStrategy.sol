// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionStrategy} from "../../interfaces/IDistributionStrategy.sol";
import {IRecipientRegistry} from "../../interfaces/IRecipientRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title BaseDistributionStrategy
/// @notice Abstract base contract for distribution strategies
/// @dev Provides common functionality for yield distribution strategies using recipient registry
abstract contract BaseDistributionStrategy is IDistributionStrategy, Ownable {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error NoRecipients();

    IERC20 public immutable yieldToken;
    IRecipientRegistry public recipientRegistry;

    constructor(address _yieldToken, address _recipientRegistry) {
        if (_yieldToken == address(0)) revert ZeroAddress();
        if (_recipientRegistry == address(0)) revert ZeroAddress();
        yieldToken = IERC20(_yieldToken);
        recipientRegistry = IRecipientRegistry(_recipientRegistry);
        _initializeOwner(msg.sender);
    }

    /// @inheritdoc IDistributionStrategy
    function distribute(uint256 amount) external virtual override {
        if (amount == 0) revert ZeroAmount();
        
        address[] memory recipients = _getRecipients();
        if (recipients.length == 0) revert NoRecipients();

        _distribute(amount, recipients);

        emit Distributed(amount);
    }

    /// @notice Sets the recipient registry
    /// @param _recipientRegistry Address of the new recipient registry
    function setRecipientRegistry(address _recipientRegistry) external onlyOwner {
        if (_recipientRegistry == address(0)) revert ZeroAddress();
        recipientRegistry = IRecipientRegistry(_recipientRegistry);
    }

    /// @dev Internal distribution logic to be implemented by concrete strategies
    /// @param amount Amount to distribute
    /// @param recipients Array of recipients to distribute to
    function _distribute(uint256 amount, address[] memory recipients) internal virtual;

    /// @dev Gets recipients from the registry
    /// @return Array of recipient addresses
    function _getRecipients() internal view returns (address[] memory) {
        return recipientRegistry.getRecipients();
    }
}
