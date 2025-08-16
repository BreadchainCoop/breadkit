// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title StrategyCalculator
/// @notice Utility library for distribution strategy calculations
/// @dev Provides calculation and validation functions for distribution strategies
library StrategyCalculator {
    error InvalidDivisor();
    error InvalidPercentages();
    error ZeroAmount();
    error PercentageOverflow();

    uint256 public constant PERCENTAGE_BASE = 10000; // 100% = 10000 basis points
    uint256 public constant MAX_PERCENTAGE = 10000;

    /// @notice Calculates the split between fixed and voted portions
    /// @param totalAmount Total amount to split
    /// @param divisor Divisor determining the split ratio
    /// @return fixedAmount Amount for fixed distribution
    /// @return votedAmount Amount for voted distribution
    function calculateSplit(uint256 totalAmount, uint256 divisor) 
        internal 
        pure 
        returns (uint256 fixedAmount, uint256 votedAmount) 
    {
        if (divisor == 0) revert InvalidDivisor();
        if (totalAmount == 0) return (0, 0);
        
        fixedAmount = totalAmount / divisor;
        votedAmount = totalAmount - fixedAmount;
    }

    /// @notice Calculates individual recipient shares based on percentages
    /// @param amount Total amount to distribute
    /// @param percentages Array of percentage allocations
    /// @return shares Array of calculated share amounts
    function calculateRecipientShares(uint256 amount, uint256[] memory percentages) 
        internal 
        pure 
        returns (uint256[] memory shares) 
    {
        if (amount == 0) revert ZeroAmount();
        
        shares = new uint256[](percentages.length);
        uint256 totalAllocated = 0;
        
        for (uint256 i = 0; i < percentages.length; i++) {
            if (i == percentages.length - 1) {
                shares[i] = amount - totalAllocated;
            } else {
                shares[i] = (amount * percentages[i]) / PERCENTAGE_BASE;
                totalAllocated += shares[i];
            }
        }
    }

    /// @notice Validates that percentages array sums to 100%
    /// @param percentages Array of percentage values
    /// @return isValid True if percentages are valid
    function validatePercentages(uint256[] memory percentages) 
        internal 
        pure 
        returns (bool isValid) 
    {
        if (percentages.length == 0) return false;
        
        uint256 total = getTotalPercentage(percentages);
        return total == PERCENTAGE_BASE;
    }

    /// @notice Calculates the total of all percentages
    /// @param percentages Array of percentage values
    /// @return total Sum of all percentages
    function getTotalPercentage(uint256[] memory percentages) 
        internal 
        pure 
        returns (uint256 total) 
    {
        for (uint256 i = 0; i < percentages.length; i++) {
            if (percentages[i] > MAX_PERCENTAGE) revert PercentageOverflow();
            total += percentages[i];
        }
    }

    /// @notice Calculates the minimum amount needed for distribution
    /// @param recipientCount Number of recipients
    /// @param minPerRecipient Minimum amount per recipient
    /// @return minTotal Minimum total amount needed
    function calculateMinimumDistribution(uint256 recipientCount, uint256 minPerRecipient) 
        internal 
        pure 
        returns (uint256 minTotal) 
    {
        return recipientCount * minPerRecipient;
    }

    /// @notice Checks if an amount can be evenly distributed
    /// @param amount Amount to check
    /// @param divisor Number to divide by
    /// @return canDistribute True if amount can be evenly distributed
    /// @return remainder Any remainder from division
    function checkEvenDistribution(uint256 amount, uint256 divisor) 
        internal 
        pure 
        returns (bool canDistribute, uint256 remainder) 
    {
        if (divisor == 0) revert InvalidDivisor();
        
        remainder = amount % divisor;
        canDistribute = remainder == 0;
    }

    /// @notice Calculates proportional distribution based on weights
    /// @param totalAmount Total amount to distribute
    /// @param weights Array of weight values
    /// @param totalWeight Sum of all weights
    /// @return distributions Array of calculated distributions
    function calculateWeightedDistribution(
        uint256 totalAmount, 
        uint256[] memory weights, 
        uint256 totalWeight
    ) 
        internal 
        pure 
        returns (uint256[] memory distributions) 
    {
        if (totalAmount == 0) revert ZeroAmount();
        if (totalWeight == 0) revert InvalidPercentages();
        
        distributions = new uint256[](weights.length);
        uint256 distributed = 0;
        
        for (uint256 i = 0; i < weights.length; i++) {
            if (i == weights.length - 1) {
                distributions[i] = totalAmount - distributed;
            } else {
                distributions[i] = (totalAmount * weights[i]) / totalWeight;
                distributed += distributions[i];
            }
        }
    }
}