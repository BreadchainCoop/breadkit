// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingPowerStrategy} from "./IVotingPowerStrategy.sol";

/// @title IVotingModule
/// @notice Interface for the voting module that manages project voting with signature-based voting
/// @dev This module is responsible for handling voting on projects and tracking voting power
interface IVotingModule {
    /// @notice Submits a vote with points for each project
    /// @dev This function records a user's vote with points for each project
    /// @param points Array of points allocated to each project
    function vote(uint256[] calldata points) external;

    /// @notice Submits a vote with points and applies multipliers
    /// @dev This function records a user's vote with points and applies specified multipliers
    /// @param points Array of points allocated to each project
    /// @param multiplierIndices Array of indices for multipliers to apply
    function voteWithMultipliers(uint256[] calldata points, uint256[] calldata multiplierIndices) external;

    /// @notice Delegates voting power to another address
    /// @dev This function allows a user to delegate their voting power to another address
    /// @param delegatee The address to delegate voting power to
    function delegate(address delegatee) external;

    /// @notice Gets the current voting power of an account
    /// @dev Returns the total voting power an account currently has
    /// @param account The address to check voting power for
    /// @return The current voting power of the account
    function getVotingPower(address account) external view returns (uint256);

    /// @notice Gets the voting power of an account for a specific time period
    /// @dev Returns the voting power an account had during a specific time period
    /// @param account The address to check voting power for
    /// @param start The start timestamp of the period
    /// @param end The end timestamp of the period
    /// @return The voting power of the account during the specified period
    function getVotingPowerForPeriod(address account, uint256 start, uint256 end) external view returns (uint256);

    /// @notice Gets the current accumulated voting power of an account
    /// @dev Returns the total accumulated voting power an account has earned
    /// @param account The address to check accumulated voting power for
    /// @return The current accumulated voting power of the account
    function getCurrentAccumulatedVotingPower(address account) external view returns (uint256);

    /// @notice Casts a vote with points for each project
    /// @dev This function is an alias for vote() and records a user's vote with points
    /// @param points Array of points allocated to each project
    function castVote(uint256[] calldata points) external;

    /// @notice Casts a vote with points and applies multipliers
    /// @dev This function is an alias for voteWithMultipliers() and records a user's vote with points and multipliers
    /// @param points Array of points allocated to each project
    /// @param multiplierIndices Array of indices for multipliers to apply
    function castVoteWithMultipliers(uint256[] calldata points, uint256[] calldata multiplierIndices) external;

    /// @notice Gets the current distribution of votes across projects
    /// @dev Returns the current voting distribution showing how votes are allocated
    /// @return An array representing the current distribution of votes
    function getCurrentVotingDistribution() external view returns (uint256[] memory);

    /// @notice Sets the maximum number of points that can be allocated
    /// @dev This determines the maximum number of points a user can allocate in a vote
    /// @param maxPoints The maximum number of points allowed
    function setMaxPoints(uint256 maxPoints) external;

    /// @notice Casts a vote with a signature
    /// @dev Allows off-chain vote preparation with on-chain submission using EIP-712 signatures
    /// @param voter The address of the voter
    /// @param points Array of points allocated to each project
    /// @param nonce The nonce for replay protection
    /// @param signature The EIP-712 signature
    function castVoteWithSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        external;

    /// @notice Casts multiple votes with signatures in a single transaction
    /// @dev Batch operation for efficient vote submission
    /// @param voters Array of voter addresses
    /// @param points Array of points arrays for each voter
    /// @param nonces Array of nonces for each voter
    /// @param signatures Array of signatures for each voter
    function castBatchVotesWithSignature(
        address[] calldata voters,
        uint256[][] calldata points,
        uint256[] calldata nonces,
        bytes[] calldata signatures
    ) external;

    /// @notice Validates vote points distribution
    /// @dev Checks if the points distribution is valid according to module rules
    /// @param points Array of points to validate
    /// @return True if points are valid, false otherwise
    function validateVotePoints(uint256[] calldata points) external view returns (bool);

    /// @notice Validates a vote signature
    /// @dev Verifies that a signature is valid for the given vote parameters
    /// @param voter The address of the voter
    /// @param points Array of points allocated to each project
    /// @param nonce The nonce for replay protection
    /// @param signature The signature to validate
    /// @return True if signature is valid, false otherwise
    function validateSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        external
        view
        returns (bool);

    /// @notice Gets the total voting power from all strategies
    /// @dev Aggregates voting power from all configured strategies
    /// @param voter The address to check voting power for
    /// @return The total voting power from all strategies
    function getTotalVotingPower(address voter) external view returns (uint256);

    /// @notice Gets the total voting power for a specific cycle
    /// @dev Returns the total voting power used in a specific cycle
    /// @param cycle The cycle number to query
    /// @return The total voting power for the cycle
    function getTotalVotingPowerForCycle(uint256 cycle) external view returns (uint256);

    /// @notice Returns the EIP-712 domain separator
    /// @dev Used for signature verification
    /// @return The domain separator hash
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice Checks if a nonce has been used for a voter
    /// @dev Used to prevent replay attacks
    /// @param voter The voter's address
    /// @param nonce The nonce to check
    /// @return True if the nonce has been used, false otherwise
    function isNonceUsed(address voter, uint256 nonce) external view returns (bool);

    /// @notice Gets all voting power strategies
    /// @dev Returns the array of configured voting power strategies
    /// @return Array of voting power strategy contracts
    function getVotingPowerStrategies() external view returns (IVotingPowerStrategy[] memory);
}
