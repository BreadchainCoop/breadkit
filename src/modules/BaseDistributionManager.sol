// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DistributionManager} from "./DistributionManager.sol";
import {IDistributionStrategy} from "../interfaces/IDistributionStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title BaseDistributionManager
/// @notice Concrete implementation of DistributionManager that manages multiple distribution strategies
/// @dev Manages distribution strategies and coordinates yield distribution
contract BaseDistributionManager is DistributionManager {
    using SafeERC20 for IERC20;

    event StrategiesInitialized(address[] strategies);
    event StrategyDistribution(address indexed strategy, uint256 amount);

    /// @notice Initializes the BaseDistributionManager with distribution strategies
    /// @param _cycleManager Address of the cycle manager
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _baseToken Address of the base token with yield
    /// @param _votingModule Address of the voting module
    /// @param _strategies Array of distribution strategy addresses to initialize with
    function initialize(
        address _cycleManager,
        address _recipientRegistry,
        address _baseToken,
        address _votingModule,
        address[] calldata _strategies
    ) external initializer {
        // Initialize parent DistributionManager
        __DistributionManager_init(_cycleManager, _recipientRegistry, _baseToken, _votingModule);

        // Add initial strategies if provided
        if (_strategies.length > 0) {
            _initializeStrategies(_strategies);
        }
    }

    /// @dev Initializes the provided strategies
    /// @param _strategies Array of strategy addresses to add
    function _initializeStrategies(address[] calldata _strategies) internal {
        for (uint256 i = 0; i < _strategies.length; i++) {
            _addStrategy(_strategies[i]);
        }
        emit StrategiesInitialized(_strategies);
    }

    /// @notice Adds a new distribution strategy
    /// @param strategy Address of the strategy to add
    function addDistributionStrategy(address strategy) external onlyOwner {
        _addStrategy(strategy);
    }

    /// @notice Removes a distribution strategy
    /// @param strategy Address of the strategy to remove
    function removeDistributionStrategy(address strategy) external onlyOwner {
        _removeStrategy(strategy);
    }

    /// @notice Sets which strategy should be the base (primary) strategy
    /// @param strategy Address of the strategy to set as base
    function setBaseDistributionStrategy(address strategy) external onlyOwner {
        if (!strategies[strategy]) revert StrategyNotFound();
        baseStrategy = IDistributionStrategy(strategy);
    }

    /// @notice Claims yield and distributes to the base strategy
    /// @dev Overrides parent to use the configured base strategy
    function claimAndDistribute() external override {
        if (!isDistributionReady()) revert DistributionNotReady();
        if (address(baseStrategy) == address(0)) revert("No base strategy set");

        // Get the amount of yield available
        uint256 yieldAmount = yieldModule.yieldAccrued();
        if (yieldAmount == 0) revert NoYieldAvailable();

        // Claim yield to this contract
        yieldModule.claimYield(yieldAmount, address(this));
        emit YieldClaimed(yieldAmount);

        // Distribute to base strategy
        _distributeToStrategy(yieldAmount);
    }

    /// @notice Distributes yield to a specific strategy
    /// @param strategy Address of the strategy to distribute to
    /// @param amount Amount to distribute
    function distributeToSpecificStrategy(address strategy, uint256 amount) external onlyOwner {
        if (!strategies[strategy]) revert StrategyNotFound();
        if (amount == 0) revert InvalidAmount();

        // Transfer tokens to strategy
        baseToken.safeTransfer(strategy, amount);

        // Trigger distribution in strategy
        IDistributionStrategy(strategy).distribute(amount);

        emit StrategyDistribution(strategy, amount);
    }

    /// @notice Distributes yield proportionally to multiple strategies
    /// @param strategyAddresses Array of strategy addresses
    /// @param proportions Array of proportions (must sum to 100)
    function distributeToMultipleStrategies(address[] calldata strategyAddresses, uint256[] calldata proportions)
        external
        onlyOwner
    {
        require(strategyAddresses.length == proportions.length, "Length mismatch");

        uint256 totalProportion = 0;
        for (uint256 i = 0; i < proportions.length; i++) {
            totalProportion += proportions[i];
        }
        require(totalProportion == 100, "Proportions must sum to 100");

        // Get available balance
        uint256 availableAmount = baseToken.balanceOf(address(this));
        require(availableAmount > 0, "No tokens to distribute");

        // Distribute to each strategy based on proportions
        for (uint256 i = 0; i < strategyAddresses.length; i++) {
            if (!strategies[strategyAddresses[i]]) revert StrategyNotFound();

            uint256 strategyAmount = (availableAmount * proportions[i]) / 100;
            if (strategyAmount > 0) {
                baseToken.safeTransfer(strategyAddresses[i], strategyAmount);
                IDistributionStrategy(strategyAddresses[i]).distribute(strategyAmount);
                emit StrategyDistribution(strategyAddresses[i], strategyAmount);
            }
        }
    }

    /// @notice Executes distribution through cycle manager
    /// @dev Can only be called by the cycle manager
    function executeDistribution() external onlyCycleManager {
        if (!isDistributionReady()) revert DistributionNotReady();
        if (address(baseStrategy) == address(0)) revert("No base strategy set");

        // Get all available yield
        uint256 yieldAmount = yieldModule.yieldAccrued();
        if (yieldAmount == 0) revert NoYieldAvailable();

        // Claim and distribute
        yieldModule.claimYield(yieldAmount, address(this));
        emit YieldClaimed(yieldAmount);

        // Distribute to base strategy
        _distributeToStrategy(yieldAmount);
    }

    /// @notice Gets all registered distribution strategies
    /// @return Array of strategy addresses
    function getDistributionStrategies() external view returns (address[] memory) {
        return strategyList;
    }

    /// @notice Checks if an address is a registered distribution strategy
    /// @param strategy Address to check
    /// @return True if registered, false otherwise
    function isDistributionStrategy(address strategy) external view returns (bool) {
        return strategies[strategy];
    }
}
