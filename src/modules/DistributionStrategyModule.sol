// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionStrategyModule} from "../interfaces/IDistributionStrategyModule.sol";
import {IDistributionStrategy} from "../interfaces/IDistributionStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title DistributionStrategyModule
/// @notice Manages yield distribution to registered strategies
/// @dev Receives yield and distributes to strategies as instructed
contract DistributionStrategyModule is IDistributionStrategyModule, Ownable {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error StrategyNotRegistered();
    error StrategyAlreadyRegistered();

    IERC20 public immutable yieldToken;
    
    mapping(address => bool) public strategies;
    address[] public strategyList;

    constructor(address _yieldToken) {
        if (_yieldToken == address(0)) revert ZeroAddress();
        yieldToken = IERC20(_yieldToken);
        _initializeOwner(msg.sender);
    }

    /// @inheritdoc IDistributionStrategyModule
    function distributeToStrategy(address strategy, uint256 amount) external override onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (!strategies[strategy]) revert StrategyNotRegistered();

        // Transfer yield to strategy and trigger distribution
        yieldToken.safeTransfer(strategy, amount);
        IDistributionStrategy(strategy).distribute(amount);

        emit YieldDistributed(strategy, amount);
    }

    /// @inheritdoc IDistributionStrategyModule
    function addStrategy(address strategy) external override onlyOwner {
        if (strategy == address(0)) revert ZeroAddress();
        if (strategies[strategy]) revert StrategyAlreadyRegistered();

        strategies[strategy] = true;
        strategyList.push(strategy);

        emit StrategyAdded(strategy);
    }

    /// @inheritdoc IDistributionStrategyModule
    function removeStrategy(address strategy) external override onlyOwner {
        if (!strategies[strategy]) revert StrategyNotRegistered();

        strategies[strategy] = false;
        
        // Remove from list
        for (uint256 i = 0; i < strategyList.length; i++) {
            if (strategyList[i] == strategy) {
                strategyList[i] = strategyList[strategyList.length - 1];
                strategyList.pop();
                break;
            }
        }

        emit StrategyRemoved(strategy);
    }

    /// @inheritdoc IDistributionStrategyModule
    function isStrategy(address strategy) external view override returns (bool) {
        return strategies[strategy];
    }

    /// @inheritdoc IDistributionStrategyModule
    function getStrategies() external view override returns (address[] memory) {
        return strategyList;
    }
}