// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@solady/contracts/auth/Ownable.sol";
import {IBreadKitToken} from "./interfaces/IBreadKitToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DefaultYieldClaimer is Ownable {
    using SafeERC20 for IERC20;

    error InvalidVotingToken();
    error InvalidInitialProjects();
    error InvalidRecipient();
    error InvalidPercentage();
    error NoYieldToClaim();
    error ClaimFailed();
    error DistributionNotReady();
    error AlreadyVoted();
    error VotingClosed();
    error InvalidVote();

    event YieldClaimed(uint256 amount);
    event YieldDistributed(address indexed recipient, uint256 amount);
    event RecipientAdded(address indexed recipient);
    event RecipientRemoved(address indexed recipient);
    event VotingStarted(uint256 indexed round, uint256 endTime);
    event Voted(address indexed voter, address indexed recipient, uint256 weight);
    event VotingFinalized(uint256 indexed round);

    struct VotingRound {
        uint256 startTime;
        uint256 endTime;
        uint256 totalVotes;
        mapping(address => uint256) votes;
        mapping(address => bool) hasVoted;
        bool finalized;
    }

    address public immutable votingToken;
    address[] public recipients;
    uint256 public percentVoted;
    uint256 public currentRound;
    uint256 public constant VOTING_DURATION = 7 days;
    uint256 public constant MIN_DISTRIBUTION_INTERVAL = 1 days;
    uint256 public lastDistribution;

    mapping(uint256 => VotingRound) public votingRounds;
    mapping(address => bool) public isRecipient;

    constructor(address votingToken_, address[] memory initialRecipients_, uint256 percentVoted_, address owner_) {
        if (votingToken_ == address(0)) revert InvalidVotingToken();
        if (initialRecipients_.length == 0) revert InvalidInitialProjects();
        if (percentVoted_ > 100) revert InvalidPercentage();

        votingToken = votingToken_;
        percentVoted = percentVoted_;

        for (uint256 i = 0; i < initialRecipients_.length; i++) {
            if (initialRecipients_[i] == address(0)) revert InvalidRecipient();
            recipients.push(initialRecipients_[i]);
            isRecipient[initialRecipients_[i]] = true;
        }

        _initializeOwner(owner_);
    }

    function claimAndDistribute() external {
        if (block.timestamp < lastDistribution + MIN_DISTRIBUTION_INTERVAL) {
            revert DistributionNotReady();
        }

        uint256 availableYield = IBreadKitToken(votingToken).yieldAccrued();
        if (availableYield == 0) revert NoYieldToClaim();

        IBreadKitToken(votingToken).claimYield(availableYield, address(this));

        uint256 votedAmount = (availableYield * percentVoted) / 100;
        uint256 equalAmount = availableYield - votedAmount;

        if (votedAmount > 0 && currentRound > 0) {
            _distributeVotedYield(votedAmount);
        }

        if (equalAmount > 0 && recipients.length > 0) {
            _distributeEqualYield(equalAmount);
        }

        lastDistribution = block.timestamp;
        emit YieldClaimed(availableYield);
    }

    function startVoting() external onlyOwner {
        VotingRound storage round = votingRounds[currentRound];
        if (round.startTime > 0 && !round.finalized) revert VotingClosed();

        currentRound++;
        votingRounds[currentRound].startTime = block.timestamp;
        votingRounds[currentRound].endTime = block.timestamp + VOTING_DURATION;

        emit VotingStarted(currentRound, votingRounds[currentRound].endTime);
    }

    function vote(address recipient) external {
        if (!isRecipient[recipient]) revert InvalidRecipient();

        VotingRound storage round = votingRounds[currentRound];
        if (round.startTime == 0) revert InvalidVote();
        if (block.timestamp > round.endTime) revert VotingClosed();
        if (round.hasVoted[msg.sender]) revert AlreadyVoted();

        uint256 votingPower = IERC20(votingToken).balanceOf(msg.sender);
        if (votingPower == 0) revert InvalidVote();

        round.votes[recipient] += votingPower;
        round.totalVotes += votingPower;
        round.hasVoted[msg.sender] = true;

        emit Voted(msg.sender, recipient, votingPower);
    }

    function finalizeVoting() external onlyOwner {
        VotingRound storage round = votingRounds[currentRound];
        if (round.startTime == 0) revert InvalidVote();
        if (block.timestamp <= round.endTime) revert VotingClosed();
        if (round.finalized) revert InvalidVote();

        round.finalized = true;
        emit VotingFinalized(currentRound);
    }

    function addRecipient(address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidRecipient();
        if (isRecipient[recipient]) revert InvalidRecipient();

        recipients.push(recipient);
        isRecipient[recipient] = true;

        emit RecipientAdded(recipient);
    }

    function removeRecipient(address recipient) external onlyOwner {
        if (!isRecipient[recipient]) revert InvalidRecipient();

        isRecipient[recipient] = false;

        uint256 length = recipients.length;
        for (uint256 i = 0; i < length; i++) {
            if (recipients[i] == recipient) {
                recipients[i] = recipients[length - 1];
                recipients.pop();
                break;
            }
        }

        emit RecipientRemoved(recipient);
    }

    function setPercentVoted(uint256 percentVoted_) external onlyOwner {
        if (percentVoted_ > 100) revert InvalidPercentage();
        percentVoted = percentVoted_;
    }

    function getRecipients() external view returns (address[] memory) {
        return recipients;
    }

    function getVotes(uint256 round, address recipient) external view returns (uint256) {
        return votingRounds[round].votes[recipient];
    }

    function _distributeVotedYield(uint256 amount) internal {
        VotingRound storage round = votingRounds[currentRound];
        if (!round.finalized || round.totalVotes == 0) return;

        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint256 votes = round.votes[recipient];
            if (votes > 0) {
                uint256 share = (amount * votes) / round.totalVotes;
                if (share > 0) {
                    IERC20(votingToken).safeTransfer(recipient, share);
                    emit YieldDistributed(recipient, share);
                }
            }
        }
    }

    function _distributeEqualYield(uint256 amount) internal {
        uint256 share = amount / recipients.length;
        for (uint256 i = 0; i < recipients.length; i++) {
            IERC20(votingToken).safeTransfer(recipients[i], share);
            emit YieldDistributed(recipients[i], share);
        }
    }
}
