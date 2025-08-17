// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionStrategy} from "../../interfaces/IDistributionStrategy.sol";
import {IDistributionStrategyModule} from "../../interfaces/IDistributionStrategyModule.sol";
import {IRecipientRegistry} from "../../interfaces/IRecipientRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title BaseDistributionStrategy
/// @notice Abstract base contract for distribution strategies that also acts as a module
/// @dev Provides common functionality for yield distribution strategies using recipient registry
///      Merges functionality from DistributionStrategyModule for single strategy deployment
abstract contract BaseDistributionStrategy is
    Initializable,
    IDistributionStrategy,
    IDistributionStrategyModule,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error NoRecipients();

    IERC20 public yieldToken;
    IRecipientRegistry public recipientRegistry;

    /// @dev Initializes the base distribution strategy
    /// @param _yieldToken Address of the yield token to distribute
    /// @param _recipientRegistry Address of the recipient registry
    function __BaseDistributionStrategy_init(address _yieldToken, address _recipientRegistry)
        internal
        onlyInitializing
    {
        __Ownable_init(msg.sender);
        __BaseDistributionStrategy_init_unchained(_yieldToken, _recipientRegistry);
    }

    function __BaseDistributionStrategy_init_unchained(address _yieldToken, address _recipientRegistry)
        internal
        onlyInitializing
    {
        if (_yieldToken == address(0)) revert ZeroAddress();
        if (_recipientRegistry == address(0)) revert ZeroAddress();
        yieldToken = IERC20(_yieldToken);
        recipientRegistry = IRecipientRegistry(_recipientRegistry);
    }

    /// @inheritdoc IDistributionStrategy
    function distribute(uint256 amount) public virtual override {
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

    // IDistributionStrategyModule implementation for single strategy

    /// @inheritdoc IDistributionStrategyModule
    function distributeToStrategy(address strategy, uint256 amount) external override onlyOwner {
        // For single strategy deployment, this contract is the strategy
        require(strategy == address(this), "Invalid strategy");
        if (amount == 0) revert ZeroAmount();

        // Pull tokens from sender and distribute
        yieldToken.safeTransferFrom(msg.sender, address(this), amount);
        distribute(amount);

        emit YieldDistributed(strategy, amount);
    }

    /// @inheritdoc IDistributionStrategyModule
    function addStrategy(address) external pure override {
        revert("Single strategy mode");
    }

    /// @inheritdoc IDistributionStrategyModule
    function removeStrategy(address) external pure override {
        revert("Single strategy mode");
    }

    /// @inheritdoc IDistributionStrategyModule
    function isStrategy(address strategy) external view override returns (bool) {
        return strategy == address(this);
    }

    /// @inheritdoc IDistributionStrategyModule
    function getStrategies() external view override returns (address[] memory) {
        address[] memory strategies = new address[](1);
        strategies[0] = address(this);
        return strategies;
    }
}
