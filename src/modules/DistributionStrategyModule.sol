// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionStrategyModule} from "../interfaces/IDistributionStrategyModule.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title DistributionStrategyModule
/// @notice Manages configurable yield distribution strategies
/// @dev Calculates the split between fixed and voted distribution portions
contract DistributionStrategyModule is IDistributionStrategyModule, Ownable {
    error InvalidDivisor();
    error DivisorTooSmall();

    uint256 public constant MIN_STRATEGY_DIVISOR = 1;
    uint256 public strategyDivisor;

    /// @notice Initializes the distribution strategy module
    /// @param _initialDivisor Initial divisor for distribution split
    constructor(uint256 _initialDivisor) {
        if (_initialDivisor == 0) revert InvalidDivisor();
        
        strategyDivisor = _initialDivisor;
        _initializeOwner(msg.sender);
    }

    /// @inheritdoc IDistributionStrategyModule
    function calculateDistribution(uint256 totalYield) 
        external 
        view 
        returns (uint256 fixedAmount, uint256 votedAmount) 
    {
        if (totalYield == 0) return (0, 0);
        
        fixedAmount = totalYield / strategyDivisor;
        votedAmount = totalYield - fixedAmount;
    }

    /// @inheritdoc IDistributionStrategyModule
    function updateDistributionStrategy(uint256 newDivisor) external onlyOwner {
        if (newDivisor == 0) revert InvalidDivisor();
        if (newDivisor < MIN_STRATEGY_DIVISOR) revert DivisorTooSmall();
        
        uint256 oldDivisor = strategyDivisor;
        strategyDivisor = newDivisor;
        
        emit DistributionStrategyUpdated(oldDivisor, newDivisor);
    }

    /// @inheritdoc IDistributionStrategyModule
    function validateStrategyConfiguration() external view returns (bool isValid) {
        return strategyDivisor > 0;
    }
}