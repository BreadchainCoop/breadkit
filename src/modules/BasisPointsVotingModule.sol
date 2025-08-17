// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractVotingModule} from "../abstracts/AbstractVotingModule.sol";
import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title BasisPointsVotingModule
/// @author BreadKit
/// @notice Concrete implementation of voting module using basis points for vote allocation
/// @dev Extends AbstractVotingModule to provide basis points-based voting functionality.
///      This module allows users to allocate voting points across multiple recipients
///      using signature-based voting for gas efficiency and better UX.
/// @custom:security-contact security@breadchain.xyz
contract BasisPointsVotingModule is AbstractVotingModule {
    function getVotingPower(address account) external view override returns (uint256) {
        return _calculateTotalVotingPower(account);
    }

    function getCurrentVotingDistribution() external view override returns (uint256[] memory) {
        uint256 currentCycle = cycleModule.getCurrentCycle();
        return projectDistributions[currentCycle];
    }

    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    function isNonceUsed(address voter, uint256 nonce) external view override returns (bool) {
        return usedNonces[voter][nonce];
    }

    function getVotingPowerStrategies() external view override returns (IVotingPowerStrategy[] memory) {
        return votingPowerStrategies;
    }

    function setMaxPoints(uint256 _maxPoints) external override onlyOwner {
        maxPoints = _maxPoints;
        emit MaxPointsSet(_maxPoints);
    }

    function validateSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        public
        view
        override
        returns (bool)
    {
        bytes32 structHash = keccak256(abi.encode(VOTE_TYPEHASH, voter, keccak256(abi.encodePacked(points)), nonce));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, signature);
        return signer == voter && !usedNonces[voter][nonce];
    }

    function validateVotePoints(uint256[] calldata points) public view override returns (bool) {
        return _validateVotePoints(points);
    }

    // ============ Constructor ============

    /// @notice Creates a new BasisPointsVotingModule instance
    /// @dev Initializes the implementation contract. Must be initialized before use.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // _disableInitializers(); // Only for proxy deployments
    }

    // ============ Initialization ============

    /// @notice Initializes the basis points voting module
    /// @dev Sets up the voting module with strategies and external dependencies.
    ///      Can only be called once due to initializer modifier.
    /// @param _maxPoints Maximum points that can be allocated per recipient (e.g., 100 for percentage-based)
    /// @param _strategies Array of voting power strategy contracts to use for power calculation
    /// @param _distributionModule Address of the distribution module for reward allocation
    /// @param _recipientRegistry Address of the recipient registry for valid recipients
    /// @param _cycleModule Address of the cycle module for cycle management
    function initialize(
        uint256 _maxPoints,
        IVotingPowerStrategy[] calldata _strategies,
        address _distributionModule,
        address _recipientRegistry,
        address _cycleModule
    ) external initializer {
        __AbstractVotingModule_init(_maxPoints, _strategies, _distributionModule, _recipientRegistry, _cycleModule);
    }

    // ============ External Functions ============

    /// @notice Casts a vote with an EIP-712 signature
    /// @dev Validates the signature and processes the vote using the voter's current voting power.
    ///      The signature must be valid and the nonce must not have been used.
    /// @param voter The address of the voter casting the vote
    /// @param points Array of basis points to allocate to each recipient (must sum to <= maxPoints per recipient)
    /// @param nonce Unique nonce for this vote to prevent replay attacks
    /// @param signature EIP-712 signature authorizing this vote
    function castVoteWithSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        external
    {
        _castSingleVote(voter, points, nonce, signature);
    }

    /// @notice Casts multiple votes in a single transaction for gas efficiency
    /// @dev Processes multiple votes atomically. If any vote fails, the entire batch reverts.
    ///      Limited to MAX_BATCH_SIZE votes per transaction to prevent gas limit issues.
    /// @param voters Array of voter addresses
    /// @param points Array of point allocations for each voter
    /// @param nonces Array of nonces for each vote
    /// @param signatures Array of EIP-712 signatures for each vote
    function castBatchVotesWithSignature(
        address[] calldata voters,
        uint256[][] calldata points,
        uint256[] calldata nonces,
        bytes[] calldata signatures
    ) external {
        // Validate array lengths match
        if (voters.length != points.length || voters.length != nonces.length || voters.length != signatures.length) {
            revert ArrayLengthMismatch();
        }

        // Check batch size limit
        if (voters.length > MAX_BATCH_SIZE) {
            revert BatchTooLarge();
        }

        // Process each vote
        for (uint256 i = 0; i < voters.length; i++) {
            _castSingleVote(voters[i], points[i], nonces[i], signatures[i]);
        }

        emit BatchVotesCast(voters, nonces);
    }

    // ============ Getter Functions ============

    /// @notice Gets the precision factor used in calculations
    /// @dev Returns the constant PRECISION value for external contracts
    /// @return The precision factor (1e18)
    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    /// @notice Gets the maximum batch size for batch voting
    /// @dev Returns the constant MAX_BATCH_SIZE value
    /// @return The maximum number of votes in a batch (50)
    function getMaxBatchSize() external pure returns (uint256) {
        return MAX_BATCH_SIZE;
    }

    /// @notice Gets the EIP-712 typehash for vote signatures
    /// @dev Returns the constant VOTE_TYPEHASH for external verification
    /// @return The keccak256 hash of the Vote type structure
    function getVoteTypehash() external pure returns (bytes32) {
        return VOTE_TYPEHASH;
    }

    // ============ View Functions ============

    /// @notice Checks if a voter has already voted in the current cycle
    /// @dev Used to determine if a vote would be a recast
    /// @param voter The address to check
    /// @return True if the voter has voted in the current cycle
    function hasVotedInCurrentCycle(address voter) external view returns (bool) {
        uint256 currentCycle = cycleModule.getCurrentCycle();
        return voterCyclePower[currentCycle][voter] > 0;
    }

    /// @notice Gets the voting power a voter used in a specific cycle
    /// @dev Returns 0 if the voter hasn't voted in that cycle
    /// @param cycle The cycle number to check
    /// @param voter The voter's address
    /// @return The voting power used by the voter in that cycle
    function getVoterCyclePower(uint256 cycle, address voter) external view returns (uint256) {
        return voterCyclePower[cycle][voter];
    }

    /// @notice Gets the points distribution a voter submitted in a specific cycle
    /// @dev Returns empty array if the voter hasn't voted in that cycle
    /// @param cycle The cycle number to check
    /// @param voter The voter's address
    /// @return Array of points the voter allocated in that cycle
    function getVoterCyclePoints(uint256 cycle, address voter) external view returns (uint256[] memory) {
        return voterCyclePoints[cycle][voter];
    }

    /// @notice Gets the total voting power used in a specific cycle
    /// @dev Useful for calculating voting participation and weight
    /// @param cycle The cycle number to check
    /// @return The total voting power used in that cycle
    function getTotalCycleVotingPower(uint256 cycle) external view returns (uint256) {
        return totalCycleVotingPower[cycle];
    }

    /// @notice Gets the vote distribution for a specific cycle
    /// @dev Returns the weighted vote totals for each recipient
    /// @param cycle The cycle number to check
    /// @return Array of weighted vote totals for each recipient
    function getProjectDistributions(uint256 cycle) external view returns (uint256[] memory) {
        return projectDistributions[cycle];
    }

    // ============ Admin Functions ============

    // Issue #43: Store required votes at proposal creation in VotingRecipientRegistry
    // https://github.com/BreadchainCoop/breadkit/issues/43
    // TODO: Implement when VotingRecipientRegistry is added
    // /// @notice Gets the required number of votes for a proposal
    // /// @dev Returns the stored required votes for proposal execution
    // /// @param proposalId The ID of the proposal
    // /// @return The number of required votes
    // function getRequiredVotes(uint256 proposalId) external view override returns (uint256) {
    //     // Will be implemented when VotingRecipientRegistry is added
    //     // return votingRecipientRegistry.getRequiredVotes(proposalId);
    // }
}
