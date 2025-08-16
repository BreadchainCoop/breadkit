// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseRecipientRegistry.sol";

/// @title VotingRecipientRegistry
/// @notice Democratic registry where all current recipients must vote to add new recipients
/// @dev Requires 100% unanimous consent from all current recipients to add new ones
/// @dev Proposals expire after 7 days if not executed
/// @author BreadKit Protocol
contract VotingRecipientRegistry is BaseRecipientRegistry {
    
    /// @notice Structure containing all information about a proposal
    /// @dev Proposals can be for adding or removing recipients
    struct Proposal {
        /// @notice The address being proposed for addition or removal
        address candidate;
        /// @notice True if this is an addition proposal, false for removal
        bool isAddition;
        /// @notice Current number of votes received for this proposal
        uint256 voteCount;
        /// @notice Mapping of addresses to whether they have voted on this proposal
        mapping(address => bool) hasVoted;
        /// @notice Whether this proposal has been executed (prevents double execution)
        bool executed;
        /// @notice Timestamp when this proposal was created (for expiry calculation)
        uint256 createdAt;
    }
    
    /// @notice Mapping from proposal ID to proposal data
    /// @dev Proposal IDs start from 0 and increment sequentially
    mapping(uint256 => Proposal) public proposals;
    
    /// @notice Total number of proposals created (also serves as next proposal ID)
    /// @dev Incremented each time a new proposal is created
    uint256 public proposalCount;
    
    /// @notice Time limit for proposals before they expire
    /// @dev Set to 7 days, after which proposals cannot be voted on or executed
    uint256 public constant PROPOSAL_EXPIRY = 7 days;
    
    // Additional Events for voting
    /// @notice Emitted when a new proposal is created
    /// @param proposalId The unique ID of the created proposal
    /// @param candidate The address being proposed for addition or removal
    /// @param isAddition True if this is an addition proposal, false for removal
    event ProposalCreated(uint256 indexed proposalId, address indexed candidate, bool isAddition);
    
    /// @notice Emitted when a recipient casts a vote on a proposal
    /// @param proposalId The ID of the proposal being voted on
    /// @param voter The address of the recipient who cast the vote
    event VoteCast(uint256 indexed proposalId, address indexed voter);
    
    /// @notice Emitted when a proposal is successfully executed
    /// @param proposalId The ID of the executed proposal
    event ProposalExecuted(uint256 indexed proposalId);
    
    /// @notice Emitted when a proposal expires without being executed
    /// @param proposalId The ID of the expired proposal
    event ProposalExpiredEvent(uint256 indexed proposalId);
    
    // Additional Errors for voting
    /// @notice Thrown when a non-recipient attempts to perform recipient-only actions
    error NotARecipient();
    
    /// @notice Thrown when attempting to access a proposal that doesn't exist
    error ProposalNotFound();
    
    /// @notice Thrown when a recipient attempts to vote on the same proposal twice
    error AlreadyVoted();
    
    /// @notice Thrown when attempting to vote on or execute a proposal that has already been executed
    error ProposalAlreadyExecuted();
    
    /// @notice Thrown when attempting to vote on or execute a proposal that has expired
    error ProposalExpired();
    
    /// @notice Thrown when attempting to execute a proposal without sufficient votes
    error NotEnoughVotes();
    
    /// @notice Thrown when attempting to initialize the registry with an empty recipients array
    error NoRecipients();

    /// @notice Initialize the registry with a set of initial recipients
    /// @dev This function replaces the constructor for upgradeable contracts
    /// @dev The admin is set but only used for emergency functions like clearing queues
    /// @dev All recipient changes after initialization must go through the voting process
    /// @dev Can only be called once due to the initializer modifier
    /// @param admin The address that will have administrative control (limited to emergency functions)
    /// @param initialRecipients Array of addresses that will be the initial voting recipients
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

    /// @notice Queue a recipient for addition through the voting process
    /// @dev This creates a proposal instead of directly queueing
    /// @dev Only existing recipients can call this function
    /// @dev The proposer automatically votes for their own proposal
    /// @param recipient Address to propose for addition to the recipient list
    function queueRecipientAddition(address recipient) external override {
        proposeAddition(recipient);
    }

    /// @notice Queue a recipient for removal through the voting process
    /// @dev This creates a proposal instead of directly queueing
    /// @dev Only existing recipients can call this function
    /// @dev The proposer automatically votes for their own proposal
    /// @param recipient Address to propose for removal from the recipient list
    function queueRecipientRemoval(address recipient) external override {
        proposeRemoval(recipient);
    }

    /// @notice Create a proposal to add a new recipient to the registry
    /// @dev Only existing recipients can create proposals
    /// @dev The proposer automatically casts the first vote
    /// @dev Proposals expire after PROPOSAL_EXPIRY time if not executed
    /// @dev Emits ProposalCreated and VoteCast events
    /// @param candidate The address to propose for addition
    /// @return proposalId The unique ID of the created proposal
    function proposeAddition(address candidate) public returns (uint256 proposalId) {
        if (!isRecipient[msg.sender]) revert NotARecipient();
        if (candidate == address(0)) revert InvalidRecipient();
        if (isRecipient[candidate]) revert RecipientAlreadyExists();
        
        proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        proposal.candidate = candidate;
        proposal.isAddition = true;
        proposal.createdAt = block.timestamp;
        
        // Proposer automatically votes for their proposal
        proposal.hasVoted[msg.sender] = true;
        proposal.voteCount = 1;
        
        emit ProposalCreated(proposalId, candidate, true);
        emit VoteCast(proposalId, msg.sender);
    }

    /// @notice Create a proposal to remove an existing recipient from the registry
    /// @dev Only existing recipients can create proposals
    /// @dev The proposer automatically casts the first vote
    /// @dev Proposals expire after PROPOSAL_EXPIRY time if not executed
    /// @dev Removal proposals require n-1 votes (all except the one being removed)
    /// @dev Emits ProposalCreated and VoteCast events
    /// @param candidate The address to propose for removal
    /// @return proposalId The unique ID of the created proposal
    function proposeRemoval(address candidate) public returns (uint256 proposalId) {
        if (!isRecipient[msg.sender]) revert NotARecipient();
        if (!isRecipient[candidate]) revert RecipientNotFound();
        
        proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        proposal.candidate = candidate;
        proposal.isAddition = false;
        proposal.createdAt = block.timestamp;
        
        // Proposer automatically votes for their proposal
        proposal.hasVoted[msg.sender] = true;
        proposal.voteCount = 1;
        
        emit ProposalCreated(proposalId, candidate, false);
        emit VoteCast(proposalId, msg.sender);
    }

    /// @notice Cast a vote on an existing proposal
    /// @dev Only existing recipients can vote on proposals
    /// @dev Voters cannot vote twice on the same proposal
    /// @dev Voting is not allowed on expired or already executed proposals
    /// @dev Automatically executes the proposal if enough votes are reached
    /// @dev Emits VoteCast event and potentially ProposalExecuted if threshold reached
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
        
        // Check if we have enough votes to execute automatically
        uint256 requiredVotes = proposal.isAddition ? recipients.length : recipients.length - 1;
        if (proposal.voteCount == requiredVotes) {
            _executeProposal(proposalId);
        }
    }

    /// @notice Manually execute a proposal that has received sufficient votes
    /// @dev Anyone can call this function if the proposal has enough votes
    /// @dev Proposals cannot be executed if they are expired or already executed
    /// @dev Addition proposals require votes from all current recipients
    /// @dev Removal proposals require votes from all recipients except the one being removed
    /// @param proposalId The ID of the proposal to execute
    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.candidate == address(0)) revert ProposalNotFound();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp > proposal.createdAt + PROPOSAL_EXPIRY) revert ProposalExpired();
        
        // Calculate required votes based on proposal type
        uint256 requiredVotes = proposal.isAddition ? recipients.length : recipients.length - 1;
        
        if (proposal.voteCount < requiredVotes) revert NotEnoughVotes();
        
        _executeProposal(proposalId);
    }

    /// @notice Internal function to execute a proposal and update recipients
    /// @dev Marks the proposal as executed to prevent double execution
    /// @dev Queues the candidate for addition or removal based on proposal type
    /// @dev Automatically processes the queue to apply changes immediately
    /// @dev Emits ProposalExecuted event after successful execution
    /// @param proposalId The ID of the proposal to execute
    function _executeProposal(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;
        
        if (proposal.isAddition) {
            _queueRecipientAddition(proposal.candidate);
        } else {
            _queueRecipientRemoval(proposal.candidate);
        }
        
        // Automatically process the queue after successful voting
        _updateRecipients();
        
        emit ProposalExecuted(proposalId);
    }

    /// @notice Get comprehensive details about a specific proposal
    /// @dev Returns all relevant information about a proposal in one call
    /// @dev Gas efficient alternative to multiple separate calls
    /// @param proposalId The ID of the proposal to query
    /// @return candidate The address being proposed for addition or removal
    /// @return isAddition Whether this is an addition (true) or removal (false) proposal
    /// @return voteCount Current number of votes the proposal has received
    /// @return executed Whether the proposal has been executed successfully
    /// @return createdAt Timestamp when the proposal was created (for expiry calculation)
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

    /// @notice Check if a specific address has voted on a proposal
    /// @dev Useful for frontend applications to show voting status
    /// @dev Returns false for non-existent proposals or voters
    /// @param proposalId The ID of the proposal to check
    /// @param voter The address to check voting status for
    /// @return hasVoted_ True if the address has voted on this proposal, false otherwise
    function hasVoted(uint256 proposalId, address voter) external view returns (bool hasVoted_) {
        return proposals[proposalId].hasVoted[voter];
    }

    /// @notice Check if a proposal has expired and can no longer be voted on
    /// @dev Proposals expire after PROPOSAL_EXPIRY time from creation
    /// @dev Expired proposals cannot receive votes or be executed
    /// @param proposalId The ID of the proposal to check
    /// @return isExpired True if the proposal has expired, false otherwise
    function isProposalExpired(uint256 proposalId) external view returns (bool isExpired) {
        Proposal storage proposal = proposals[proposalId];
        return block.timestamp > proposal.createdAt + PROPOSAL_EXPIRY;
    }

    /// @notice Calculate the number of votes required for a proposal to pass
    /// @dev Addition proposals require all current recipients to vote (100% consensus)
    /// @dev Removal proposals require all recipients except the one being removed
    /// @dev This number can change if recipients are added/removed while proposal is active
    /// @param proposalId The ID of the proposal to check requirements for
    /// @return requiredVotes Number of votes needed for the proposal to be executable
    function getRequiredVotes(uint256 proposalId) external view returns (uint256 requiredVotes) {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.candidate == address(0)) revert ProposalNotFound();
        
        // Addition proposals need unanimous consent from all current recipients
        // Removal proposals need consent from all recipients except the one being removed
        return proposal.isAddition ? recipients.length : recipients.length - 1;
    }
}