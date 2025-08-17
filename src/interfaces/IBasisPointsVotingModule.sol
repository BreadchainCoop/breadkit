// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingPowerStrategy} from "./IVotingPowerStrategy.sol";

/// @title IBasisPointsVotingModule
/// @notice Interface for the basis points voting module that manages project voting with signature-based voting
/// @dev This module is responsible for handling voting on projects using basis points and tracking voting power
interface IBasisPointsVotingModule {
    /// @notice Gets the current voting power of an account
    /// @dev Returns the total voting power an account currently has
    /// @param account The address to check voting power for
    /// @return The current voting power of the account
    function getVotingPower(address account) external view returns (uint256);

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

    // Issue #43: Store required votes at proposal creation in VotingRecipientRegistry
    // https://github.com/BreadchainCoop/breadkit/issues/43
    // TODO: Implement when VotingRecipientRegistry is added
    // /// @notice Gets the required number of votes for a proposal
    // /// @dev Returns the stored required votes for proposal execution
    // /// @param proposalId The ID of the proposal
    // /// @return The number of required votes
    // function getRequiredVotes(uint256 proposalId) external view returns (uint256);
}
