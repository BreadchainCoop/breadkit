// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// TODO: Implement TimeWeightedVotingPower in a future release
// Issue: https://github.com/BreadchainCoop/breadkit/issues/48
// 
// The TimeWeightedVotingPower strategy will calculate voting power based on how long
// tokens were held during a specific period, encouraging long-term holding and participation.
// This follows the breadchain pattern for fair distribution.
//
// Implementation requirements:
// - Calculate voting power based on token holding duration
// - Support configurable time periods for weight calculation  
// - Integrate with cycle management for proper period tracking
// - Handle edge cases for mid-period token transfers
//
// Commented out for initial release - to be implemented in a future version

/*
import {IVotingPowerStrategy} from "../../interfaces/IVotingPowerStrategy.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title TimeWeightedVotingPower
/// @author BreadKit
/// @notice Time-weighted voting power calculation strategy based on breadchain pattern
/// @dev Implements IVotingPowerStrategy with time-weighted calculations.
///      Voting power is calculated based on how long tokens were held during a specific period.
///      This encourages long-term holding and participation.
contract TimeWeightedVotingPower is IVotingPowerStrategy, Ownable {
    using Checkpoints for Checkpoints.Trace208;

    // ============ Errors ============

    /// @notice Thrown when attempting to initialize with zero address token
    error InvalidToken();

    /// @notice Thrown when start block is not before end block
    error StartMustBeBeforeEnd();

    /// @notice Thrown when end block is in the future
    error EndAfterCurrentBlock();

    // ============ Immutable Storage ============

    /// @notice The ERC20Votes token used for voting power calculation
    /// @dev Must implement the IVotes interface from OpenZeppelin
    IVotes public immutable votingToken;

    // ============ State Variables ============

    /// @notice Block number when the previous voting cycle started
    uint256 public previousCycleStart;

    /// @notice Block number when yield was last claimed
    uint256 public lastClaimedBlock;

    // ============ Events ============

    /// @notice Emitted when cycle bounds are updated
    /// @param previousCycleStart New previous cycle start block
    /// @param lastClaimedBlock New last claimed block
    event CycleBoundsUpdated(uint256 previousCycleStart, uint256 lastClaimedBlock);

    /// @notice Constructs the time-weighted voting power strategy
    /// @dev Initializes the strategy with a voting token and cycle bounds
    /// @param _votingToken The ERC20Votes token to use for voting power calculation
    /// @param _previousCycleStart The start block of the previous cycle
    /// @param _lastClaimedBlock The last block where yield was claimed
    constructor(IVotes _votingToken, uint256 _previousCycleStart, uint256 _lastClaimedBlock) {
        if (address(_votingToken) == address(0)) revert InvalidToken();
        votingToken = _votingToken;
        previousCycleStart = _previousCycleStart;
        lastClaimedBlock = _lastClaimedBlock;
        _initializeOwner(msg.sender);
    }

    /// @inheritdoc IVotingPowerStrategy
    function getCurrentVotingPower(address account) external view override returns (uint256) {
        // Time-weighted power for current cycle (breadchain pattern)
        return getVotingPowerForPeriod(account, previousCycleStart, lastClaimedBlock);
    }

    /// @notice Calculates time-weighted voting power for a specific period
    /// @dev Uses a simplified average of start and end voting power weighted by period length.
    ///      Reverts if start >= end or if end > current block.
    /// @param account The account to calculate voting power for
    /// @param start The start block of the period (inclusive)
    /// @param end The end block of the period (inclusive)
    /// @return The time-weighted voting power for the period
    function getVotingPowerForPeriod(address account, uint256 start, uint256 end) public view returns (uint256) {
        if (start >= end) revert StartMustBeBeforeEnd();
        if (end > block.number) revert EndAfterCurrentBlock();

        // Use the voting token directly as IVotes

        // Simplified implementation: use average of start and end voting power
        // weighted by the period length
        uint256 startPower = start > 0 ? votingToken.getPastVotes(account, start - 1) : 0;
        uint256 endPower = votingToken.getPastVotes(account, end - 1);

        // If no voting power at end, return 0
        if (endPower == 0 && startPower == 0) return 0;

        // Calculate average power weighted by time
        uint256 averagePower = (startPower + endPower) / 2;
        uint256 periodLength = end - start;

        // Return time-weighted power
        return averagePower * periodLength;
    }

    /// @notice Updates the cycle bounds for voting power calculations
    /// @dev Only callable by owner. Used to synchronize with yield distribution cycles.
    /// @param _previousCycleStart New previous cycle start block
    /// @param _lastClaimedBlock New last claimed block
    function updateCycleBounds(uint256 _previousCycleStart, uint256 _lastClaimedBlock) external onlyOwner {
        previousCycleStart = _previousCycleStart;
        lastClaimedBlock = _lastClaimedBlock;
        emit CycleBoundsUpdated(_previousCycleStart, _lastClaimedBlock);
    }
}
*/