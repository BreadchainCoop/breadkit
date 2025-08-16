// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IDistributionModule
/// @notice Interface for the distribution module that manages yield distribution
/// @dev This module is responsible for orchestrating the entire distribution process across all modules
interface IDistributionModule {
    struct DistributionState {
        uint256 totalYield;
        uint256 fixedAmount;
        uint256 votedAmount;
        uint256 totalVotes;
        uint256 lastDistributionBlock;
        uint256 cycleNumber;
        address[] recipients;
        uint256[] votedDistributions;
        uint256[] fixedDistributions;
    }

    event YieldDistributed(
        uint256 totalYield,
        uint256 totalVotes,
        address[] recipients,
        uint256[] votedDistributions,
        uint256[] fixedDistributions
    );
    
    event TokensMintedForDistribution(uint256 amount);
    event EmergencyPause(address admin, uint256 timestamp);
    event EmergencyWithdraw(address token, address to, uint256 amount, address admin);
    event CycleCompleted(uint256 cycleNumber, uint256 blockNumber);
    event DistributionValidated(uint256 totalYield, uint256 recipientCount);

    /// @notice Distributes yield to recipients based on voting and fixed allocations
    /// @dev Orchestrates the entire distribution process including yield collection, calculation, and transfer
    function distributeYield() external;

    /// @notice Gets the current state of the distribution system
    /// @dev Returns comprehensive information about the current distribution state
    /// @return state The current distribution state including all relevant parameters
    function getCurrentDistributionState() external view returns (DistributionState memory state);

    /// @notice Validates if distribution conditions are met
    /// @dev Checks if all prerequisites for distribution are satisfied
    /// @return canDistribute Whether distribution can proceed
    /// @return reason If cannot distribute, the reason why
    function validateDistribution() external view returns (bool canDistribute, string memory reason);

    /// @notice Emergency pause function to halt distributions
    /// @dev Can only be called by emergency admin
    function emergencyPause() external;

    /// @notice Resume distributions after emergency pause
    /// @dev Can only be called by owner
    function emergencyResume() external;

    /// @notice Sets the cycle length for distributions
    /// @dev Determines the minimum blocks between distributions
    /// @param _cycleLength The cycle length in blocks
    function setCycleLength(uint256 _cycleLength) external;

    /// @notice Sets the fixed split divisor
    /// @dev Determines the portion allocated to fixed distribution
    /// @param _divisor The divisor for fixed split calculation
    function setYieldFixedSplitDivisor(uint256 _divisor) external;

    /// @notice Sets the voting module address
    /// @dev Connects the distribution module to the voting system
    /// @param _votingModule Address of the voting module
    function setVotingModule(address _votingModule) external;

    /// @notice Sets the fixed split module address
    /// @dev Connects the distribution module to the fixed split system
    /// @param _fixedSplitModule Address of the fixed split module
    function setFixedSplitModule(address _fixedSplitModule) external;

    /// @notice Sets the recipient registry address
    /// @dev Connects the distribution module to the recipient management system
    /// @param _recipientRegistry Address of the recipient registry
    function setRecipientRegistry(address _recipientRegistry) external;

    /// @notice Sets the yield collector address
    /// @dev Connects the distribution module to the yield collection system
    /// @param _yieldCollector Address of the yield collector
    function setYieldCollector(address _yieldCollector) external;
}
