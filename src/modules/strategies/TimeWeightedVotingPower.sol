// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingPowerStrategy} from "../../interfaces/IVotingPowerStrategy.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title TimeWeightedVotingPower
/// @notice Time-weighted voting power calculation strategy based on breadchain pattern
/// @dev Calculates voting power weighted by time held during a period
contract TimeWeightedVotingPower is IVotingPowerStrategy, Ownable {
    using Checkpoints for Checkpoints.Trace208;

    // Errors
    error InvalidToken();
    error StartMustBeBeforeEnd();
    error EndAfterCurrentBlock();

    // Storage
    IVotes public immutable votingToken;
    uint256 public previousCycleStart;
    uint256 public lastClaimedBlock;

    // Events
    event CycleBoundsUpdated(uint256 previousCycleStart, uint256 lastClaimedBlock);

    /// @notice Constructs the time-weighted voting power strategy
    /// @param _votingToken The token to use for voting power calculation
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

    /// @inheritdoc IVotingPowerStrategy
    function getAccumulatedVotingPower(address account) external view override returns (uint256) {
        // Accumulated power since last cycle
        return getVotingPowerForPeriod(account, lastClaimedBlock, block.number);
    }

    /// @notice Get voting power for a specific period (simplified implementation)
    /// @dev Simplified time-weighted calculation using available IVotes interface
    /// @param account The account to calculate voting power for
    /// @param start The start block of the period
    /// @param end The end block of the period
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

    /// @notice Updates the cycle bounds
    /// @param _previousCycleStart New previous cycle start block
    /// @param _lastClaimedBlock New last claimed block
    function updateCycleBounds(uint256 _previousCycleStart, uint256 _lastClaimedBlock) external onlyOwner {
        previousCycleStart = _previousCycleStart;
        lastClaimedBlock = _lastClaimedBlock;
        emit CycleBoundsUpdated(_previousCycleStart, _lastClaimedBlock);
    }
}
