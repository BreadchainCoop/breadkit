// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingPowerStrategy} from "../../interfaces/IVotingPowerStrategy.sol";
import {IBreadKitToken} from "../../interfaces/IBreadKitToken.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title TokenBasedVotingPower
/// @notice Simple token balance-based voting power calculation strategy
/// @dev Calculates voting power based on token holdings without staking
contract TokenBasedVotingPower is IVotingPowerStrategy {
    // Errors
    error InvalidToken();

    // Storage
    IBreadKitToken public immutable votingToken;

    /// @notice Constructs the token-based voting power strategy
    /// @param _votingToken The token to use for voting power calculation
    constructor(IBreadKitToken _votingToken) {
        if (address(_votingToken) == address(0)) revert InvalidToken();
        votingToken = _votingToken;
    }

    /// @inheritdoc IVotingPowerStrategy
    function getCurrentVotingPower(address account) external view override returns (uint256) {
        // Use delegated votes (or balance if not delegated) for voting power
        return IVotes(address(votingToken)).getVotes(account);
    }

    /// @inheritdoc IVotingPowerStrategy
    function getAccumulatedVotingPower(address account) external view override returns (uint256) {
        // For token-based strategy, accumulated power equals current power
        return IVotes(address(votingToken)).getVotes(account);
    }
}
