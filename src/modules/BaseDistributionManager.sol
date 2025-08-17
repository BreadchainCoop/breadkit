// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DistributionManager} from "./DistributionManager.sol";
import {EqualDistributionStrategy} from "./strategies/EqualDistributionStrategy.sol";
import {IDistributionStrategy} from "../interfaces/IDistributionStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title BaseDistributionManager
/// @notice Concrete implementation of DistributionManager that uses EqualDistributionStrategy
/// @dev Deploys and manages an EqualDistributionStrategy for yield distribution
contract BaseDistributionManager is DistributionManager {
    using SafeERC20 for IERC20;

    EqualDistributionStrategy public equalDistributionStrategy;

    event EqualDistributionStrategyDeployed(address indexed strategy);

    /// @notice Initializes the BaseDistributionManager with an EqualDistributionStrategy
    /// @param _cycleManager Address of the cycle manager
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _baseToken Address of the base token with yield
    /// @param _votingModule Address of the voting module
    function initialize(address _cycleManager, address _recipientRegistry, address _baseToken, address _votingModule)
        external
        initializer
    {
        // Initialize parent DistributionManager
        __DistributionManager_init(_cycleManager, _recipientRegistry, _baseToken, _votingModule);

        // Deploy and initialize EqualDistributionStrategy
        _deployEqualDistributionStrategy(_baseToken, _recipientRegistry);
    }

    /// @dev Deploys and initializes the EqualDistributionStrategy
    /// @param _baseToken Address of the token to distribute
    /// @param _recipientRegistry Address of the recipient registry
    function _deployEqualDistributionStrategy(address _baseToken, address _recipientRegistry) internal {
        // Deploy new EqualDistributionStrategy
        equalDistributionStrategy = new EqualDistributionStrategy();

        // Initialize the strategy with this contract as the distribution manager
        equalDistributionStrategy.initialize(_baseToken, _recipientRegistry, address(this));

        // Add the strategy to the distribution manager's strategy list
        _addStrategy(address(equalDistributionStrategy));

        // Set it as the base strategy in parent (already done in _addStrategy if first strategy)
        baseStrategy = IDistributionStrategy(address(equalDistributionStrategy));

        emit EqualDistributionStrategyDeployed(address(equalDistributionStrategy));
    }

    /// @notice Claims yield and distributes equally to all recipients
    /// @dev Overrides parent to ensure equal distribution strategy is used
    function claimAndDistribute() external override {
        if (!isDistributionReady()) revert DistributionNotReady();

        // Get the amount of yield available
        uint256 yieldAmount = yieldModule.yieldAccrued();
        if (yieldAmount == 0) revert NoYieldAvailable();

        // Claim yield to this contract
        yieldModule.claimYield(yieldAmount, address(this));
        emit YieldClaimed(yieldAmount);

        // Transfer to equal distribution strategy and trigger distribution
        baseToken.safeTransfer(address(equalDistributionStrategy), yieldAmount);
        equalDistributionStrategy.distribute(yieldAmount);

        emit YieldDistributed(address(equalDistributionStrategy), yieldAmount);
    }

    /// @notice Gets the address of the equal distribution strategy
    /// @return Address of the EqualDistributionStrategy contract
    function getEqualDistributionStrategy() external view returns (address) {
        return address(equalDistributionStrategy);
    }

    /// @notice Executes distribution through cycle manager
    /// @dev Can only be called by the cycle manager
    function executeDistribution() external onlyCycleManager {
        if (!isDistributionReady()) revert DistributionNotReady();

        // Get all available yield
        uint256 yieldAmount = yieldModule.yieldAccrued();
        if (yieldAmount == 0) revert NoYieldAvailable();

        // Claim and distribute
        yieldModule.claimYield(yieldAmount, address(this));
        emit YieldClaimed(yieldAmount);

        baseToken.safeTransfer(address(equalDistributionStrategy), yieldAmount);
        equalDistributionStrategy.distribute(yieldAmount);

        emit YieldDistributed(address(equalDistributionStrategy), yieldAmount);
    }
}
