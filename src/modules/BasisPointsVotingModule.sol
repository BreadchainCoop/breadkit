// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractVotingModule} from "../abstracts/AbstractVotingModule.sol";
import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";

/// @title BasisPointsVotingModule
/// @author BreadKit
/// @notice Concrete implementation of voting module using basis points for vote allocation
/// @dev Extends AbstractVotingModule to provide basis points-based voting functionality.
///      This module allows users to allocate voting points across multiple recipients
///      using signature-based voting for gas efficiency and better UX.
/// @custom:security-contact security@breadchain.xyz
contract BasisPointsVotingModule is AbstractVotingModule {
    // ============ Storage Variables ============

    /// @notice Maximum points that can be allocated to a single recipient
    /// @dev Configurable per implementation to control vote distribution
    uint256 public maxPoints;

    /// @notice Vote distribution across projects for each cycle
    /// @dev cycle => array of weighted votes per project
    mapping(uint256 => uint256[]) public projectDistributions;

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
        maxPoints = _maxPoints;
        __AbstractVotingModule_init(_strategies, _distributionModule, _recipientRegistry, _cycleModule);
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

    // ============ View Functions ============

    /// @notice Gets the current voting distribution for the active cycle
    /// @dev Returns the array of weighted votes for each project in the current cycle
    /// @return Array of vote weights for each project
    function getCurrentVotingDistribution() external view returns (uint256[] memory) {
        uint256 currentCycle = cycleModule.getCurrentCycle();
        return projectDistributions[currentCycle];
    }

    /// @notice Gets the vote distribution for a specific cycle
    /// @dev Returns the weighted vote totals for each recipient
    /// @param cycle The cycle number to check
    /// @return Array of weighted vote totals for each recipient
    function getProjectDistributions(uint256 cycle) external view returns (uint256[] memory) {
        return projectDistributions[cycle];
    }

    // ============ Admin Functions ============

    /// @notice Sets the maximum points that can be allocated per recipient
    /// @dev Only callable by owner
    /// @param _maxPoints The new maximum points value
    function setMaxPoints(uint256 _maxPoints) external onlyOwner {
        maxPoints = _maxPoints;
        emit MaxPointsSet(_maxPoints);
    }

    // ============ Internal Functions ============

    /// @notice Processes and records a vote
    /// @dev Updates project distributions and cycle voting power. Handles vote recasting.
    /// @param voter Address of the voter
    /// @param points Array of points allocated to each recipient
    /// @param votingPower Total voting power of the voter
    function _processVote(address voter, uint256[] calldata points, uint256 votingPower) internal override {
        uint256 currentCycle = cycleModule.getCurrentCycle();

        // Check if voter has already voted in this cycle and revert their previous vote
        uint256 previousVotingPower = voterCyclePower[currentCycle][voter];
        if (previousVotingPower > 0) {
            // Revert previous vote's impact on total voting power
            totalCycleVotingPower[currentCycle] -= previousVotingPower;

            // Revert previous vote's impact on project distributions
            uint256[] storage previousPoints = voterCyclePoints[currentCycle][voter];
            for (uint256 i = 0; i < previousPoints.length; i++) {
                uint256 previousAllocation = (previousVotingPower * previousPoints[i]) / PRECISION;
                projectDistributions[currentCycle][i] -= previousAllocation;
            }
        }

        // Apply new vote
        totalCycleVotingPower[currentCycle] += votingPower;

        // Store voter's current voting power and points for potential future recasting
        voterCyclePower[currentCycle][voter] = votingPower;
        delete voterCyclePoints[currentCycle][voter]; // Clear previous points array
        for (uint256 i = 0; i < points.length; i++) {
            voterCyclePoints[currentCycle][voter].push(points[i]);
        }

        // Calculate and update project distributions with new vote
        for (uint256 i = 0; i < points.length; i++) {
            uint256 allocation = (votingPower * points[i]) / PRECISION;

            // Update project distributions
            if (i >= projectDistributions[currentCycle].length) {
                projectDistributions[currentCycle].push(allocation);
            } else {
                projectDistributions[currentCycle][i] += allocation;
            }
        }

        // Update last voted cycle
        accountLastVotedCycle[voter] = currentCycle;
    }

    /// @notice Validates vote points distribution
    /// @dev Checks if points array is valid according to basis points rules
    /// @param points Array of points to validate
    /// @return True if points are valid, false otherwise
    function _validateVotePoints(uint256[] calldata points) internal view override returns (bool) {
        if (points.length == 0) return false;

        // Validate array length against recipient registry
        uint256 recipientCount = recipientRegistry.getRecipientCount();
        if (points.length != recipientCount) return false;

        uint256 totalPoints;
        for (uint256 i = 0; i < points.length; i++) {
            if (points[i] > maxPoints) return false;
            totalPoints += points[i];
        }

        return totalPoints > 0;
    }

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
