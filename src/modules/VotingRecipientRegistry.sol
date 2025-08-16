// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title VotingRecipientRegistry
/// @notice Registry where all current recipients must vote to add new recipients
/// @dev Requires 100% unanimous consent from all current recipients to add new ones
contract VotingRecipientRegistry is OwnableUpgradeable {
    
    struct Proposal {
        address candidate;
        bool isAddition; // true for addition, false for removal
        uint256 voteCount;
        mapping(address => bool) hasVoted;
        bool executed;
        uint256 createdAt;
    }
    
    // Active recipients
    address[] public recipients;
    
    // Mapping to check if address is an active recipient
    mapping(address => bool) public isRecipient;
    
    // Proposals
    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    
    // Proposal expiry time (7 days)
    uint256 public constant PROPOSAL_EXPIRY = 7 days;
    
    // Events
    event RecipientAdded(address indexed recipient);
    event RecipientRemoved(address indexed recipient);
    event ProposalCreated(uint256 indexed proposalId, address indexed candidate, bool isAddition);
    event VoteCast(uint256 indexed proposalId, address indexed voter);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalExpiredEvent(uint256 indexed proposalId);
    
    // Errors
    error InvalidRecipient();
    error RecipientAlreadyExists();
    error RecipientNotFound();
    error NotARecipient();
    error ProposalNotFound();
    error AlreadyVoted();
    error ProposalAlreadyExecuted();
    error ProposalExpired();
    error NotEnoughVotes();
    error NoRecipients();

    /// @notice Initialize the registry with initial recipients
    /// @param admin The admin address (for initial setup only)
    /// @param initialRecipients The initial set of recipients
    function initialize(address admin, address[] memory initialRecipients) public initializer {
        __Ownable_init(admin);
        
        if (initialRecipients.length == 0) revert NoRecipients();
        
        for (uint256 i = 0; i < initialRecipients.length; i++) {
            address recipient = initialRecipients[i];
            if (recipient == address(0)) revert InvalidRecipient();
            if (isRecipient[recipient]) revert RecipientAlreadyExists();
            
            recipients.push(recipient);
            isRecipient[recipient] = true;
            emit RecipientAdded(recipient);
        }
    }

    /// @notice Propose adding a new recipient
    /// @param candidate Address to propose for addition
    /// @return proposalId The ID of the created proposal
    function proposeAddition(address candidate) external returns (uint256 proposalId) {
        if (!isRecipient[msg.sender]) revert NotARecipient();
        if (candidate == address(0)) revert InvalidRecipient();
        if (isRecipient[candidate]) revert RecipientAlreadyExists();
        
        proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        proposal.candidate = candidate;
        proposal.isAddition = true;
        proposal.createdAt = block.timestamp;
        
        // Proposer automatically votes
        proposal.hasVoted[msg.sender] = true;
        proposal.voteCount = 1;
        
        emit ProposalCreated(proposalId, candidate, true);
        emit VoteCast(proposalId, msg.sender);
    }

    /// @notice Propose removing an existing recipient
    /// @param candidate Address to propose for removal
    /// @return proposalId The ID of the created proposal
    function proposeRemoval(address candidate) external returns (uint256 proposalId) {
        if (!isRecipient[msg.sender]) revert NotARecipient();
        if (!isRecipient[candidate]) revert RecipientNotFound();
        
        proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        proposal.candidate = candidate;
        proposal.isAddition = false;
        proposal.createdAt = block.timestamp;
        
        // Proposer automatically votes
        proposal.hasVoted[msg.sender] = true;
        proposal.voteCount = 1;
        
        emit ProposalCreated(proposalId, candidate, false);
        emit VoteCast(proposalId, msg.sender);
    }

    /// @notice Vote on a proposal
    /// @param proposalId The ID of the proposal to vote on
    function vote(uint256 proposalId) external {
        if (!isRecipient[msg.sender]) revert NotARecipient();
        
        Proposal storage proposal = proposals[proposalId];
        if (proposal.candidate == address(0)) revert ProposalNotFound();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp > proposal.createdAt + PROPOSAL_EXPIRY) revert ProposalExpired();
        if (proposal.hasVoted[msg.sender]) revert AlreadyVoted();
        
        proposal.hasVoted[msg.sender] = true;
        proposal.voteCount++;
        
        emit VoteCast(proposalId, msg.sender);
        
        // Check if we have enough votes to execute
        uint256 requiredVotes = proposal.isAddition ? recipients.length : recipients.length - 1;
        if (proposal.voteCount == requiredVotes) {
            _executeProposal(proposalId);
        }
    }

    /// @notice Execute a proposal that has unanimous consent
    /// @param proposalId The ID of the proposal to execute
    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.candidate == address(0)) revert ProposalNotFound();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp > proposal.createdAt + PROPOSAL_EXPIRY) revert ProposalExpired();
        
        // For additions, need all current recipients to vote
        // For removals, need all recipients except the one being removed
        uint256 requiredVotes = proposal.isAddition ? recipients.length : recipients.length - 1;
        
        if (proposal.voteCount < requiredVotes) revert NotEnoughVotes();
        
        _executeProposal(proposalId);
    }

    /// @notice Internal function to execute a proposal
    function _executeProposal(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        
        if (proposal.isAddition) {
            recipients.push(proposal.candidate);
            isRecipient[proposal.candidate] = true;
            emit RecipientAdded(proposal.candidate);
        } else {
            isRecipient[proposal.candidate] = false;
            
            // Remove from array
            for (uint256 i = 0; i < recipients.length; i++) {
                if (recipients[i] == proposal.candidate) {
                    recipients[i] = recipients[recipients.length - 1];
                    recipients.pop();
                    break;
                }
            }
            
            emit RecipientRemoved(proposal.candidate);
        }
        
        emit ProposalExecuted(proposalId);
    }

    /// @notice Get proposal details
    /// @param proposalId The ID of the proposal
    /// @return candidate The address being proposed
    /// @return isAddition Whether this is an addition (true) or removal (false)
    /// @return voteCount Number of votes received
    /// @return executed Whether the proposal has been executed
    /// @return createdAt Timestamp when proposal was created
    function getProposal(uint256 proposalId) external view returns (
        address candidate,
        bool isAddition,
        uint256 voteCount,
        bool executed,
        uint256 createdAt
    ) {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.candidate,
            proposal.isAddition,
            proposal.voteCount,
            proposal.executed,
            proposal.createdAt
        );
    }

    /// @notice Check if an address has voted on a proposal
    /// @param proposalId The ID of the proposal
    /// @param voter The address to check
    /// @return Whether the address has voted
    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return proposals[proposalId].hasVoted[voter];
    }

    /// @notice Get all active recipients
    /// @return Array of active recipient addresses
    function getRecipients() external view returns (address[] memory) {
        return recipients;
    }

    /// @notice Get count of active recipients
    /// @return Number of active recipients
    function getRecipientCount() external view returns (uint256) {
        return recipients.length;
    }

    /// @notice Check if a proposal is expired
    /// @param proposalId The ID of the proposal
    /// @return Whether the proposal is expired
    function isProposalExpired(uint256 proposalId) external view returns (bool) {
        Proposal storage proposal = proposals[proposalId];
        return block.timestamp > proposal.createdAt + PROPOSAL_EXPIRY;
    }

    /// @notice Get required votes for a proposal
    /// @param proposalId The ID of the proposal
    /// @return Number of votes required for the proposal to pass
    function getRequiredVotes(uint256 proposalId) external view returns (uint256) {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.candidate == address(0)) revert ProposalNotFound();
        
        // For additions, need all current recipients
        // For removals, need all recipients except the one being removed
        return proposal.isAddition ? recipients.length : recipients.length - 1;
    }
}