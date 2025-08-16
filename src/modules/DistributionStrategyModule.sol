// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionStrategyModule} from "../interfaces/IDistributionStrategyModule.sol";
import {IDistributionStrategy} from "../interfaces/IDistributionStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title DistributionStrategyModule
/// @notice Orchestrates yield distribution between equal and voting strategies
/// @dev Manages the split ratio and distribution to different strategies
contract DistributionStrategyModule is IDistributionStrategyModule, Ownable {
    using SafeERC20 for IERC20;

    error InvalidDivisor();
    error ZeroAddress();
    error ZeroAmount();
    error StrategiesNotSet();

    uint256 public constant MIN_DIVISOR = 1;

    IERC20 public immutable yieldToken;
    IDistributionStrategy public equalDistributionStrategy;
    IDistributionStrategy public votingDistributionStrategy;
    uint256 public splitDivisor;

    constructor(address _yieldToken, uint256 _initialDivisor) {
        if (_yieldToken == address(0)) revert ZeroAddress();
        if (_initialDivisor == 0) revert InvalidDivisor();

        yieldToken = IERC20(_yieldToken);
        splitDivisor = _initialDivisor;
        _initializeOwner(msg.sender);
    }

    /// @notice Sets the distribution strategies
    /// @param _equalStrategy Address of equal distribution strategy
    /// @param _votingStrategy Address of voting distribution strategy
    function setStrategies(address _equalStrategy, address _votingStrategy) external onlyOwner {
        if (_equalStrategy == address(0) || _votingStrategy == address(0)) revert ZeroAddress();

        equalDistributionStrategy = IDistributionStrategy(_equalStrategy);
        votingDistributionStrategy = IDistributionStrategy(_votingStrategy);

        emit StrategiesUpdated(_equalStrategy, _votingStrategy);
    }

    /// @inheritdoc IDistributionStrategyModule
    function distributeYield(uint256 totalYield) external override {
        if (totalYield == 0) revert ZeroAmount();
        if (address(equalDistributionStrategy) == address(0) || address(votingDistributionStrategy) == address(0)) {
            revert StrategiesNotSet();
        }

        (uint256 equalAmount, uint256 votingAmount) = calculateSplit(totalYield);

        // Transfer and distribute to equal strategy
        if (equalAmount > 0) {
            yieldToken.safeTransfer(address(equalDistributionStrategy), equalAmount);
            equalDistributionStrategy.distribute(equalAmount);
        }

        // Transfer and distribute to voting strategy
        if (votingAmount > 0) {
            yieldToken.safeTransfer(address(votingDistributionStrategy), votingAmount);
            votingDistributionStrategy.distribute(votingAmount);
        }

        emit YieldDistributed(totalYield, equalAmount, votingAmount);
    }

    /// @inheritdoc IDistributionStrategyModule
    function updateSplitRatio(uint256 divisor) external override onlyOwner {
        if (divisor < MIN_DIVISOR) revert InvalidDivisor();

        uint256 oldDivisor = splitDivisor;
        splitDivisor = divisor;

        emit SplitRatioUpdated(oldDivisor, divisor);
    }

    /// @inheritdoc IDistributionStrategyModule
    function calculateSplit(uint256 totalYield)
        public
        view
        override
        returns (uint256 equalAmount, uint256 votingAmount)
    {
        if (totalYield == 0) return (0, 0);

        equalAmount = totalYield / splitDivisor;
        votingAmount = totalYield - equalAmount;
    }
}
