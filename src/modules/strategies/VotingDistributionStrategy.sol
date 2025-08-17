// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseDistributionStrategy} from "./BaseDistributionStrategy.sol";
import {IVotingModule} from "../../interfaces/IVotingModule.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title VotingDistributionStrategy
/// @notice Distributes yield based on voting results
/// @dev Implements proportional distribution based on vote counts using recipient registry
contract VotingDistributionStrategy is BaseDistributionStrategy {
    using SafeERC20 for IERC20;

    IVotingModule public votingModule;

    error InvalidVotesLength();

    constructor(address _yieldToken, address _recipientRegistry, address _votingModule) 
        BaseDistributionStrategy(_yieldToken, _recipientRegistry) {
        if (_votingModule == address(0)) revert ZeroAddress();
        votingModule = IVotingModule(_votingModule);
    }

    /// @dev Distributes amount based on voting weights
    /// @param amount Total amount to distribute
    /// @param recipients Array of recipients to distribute to
    function _distribute(uint256 amount, address[] memory recipients) internal override {
        uint256[] memory currentVotes = votingModule.getCurrentVotingDistribution();
        if (currentVotes.length != recipients.length) revert InvalidVotesLength();

        uint256 totalVotes = 0;
        for (uint256 i = 0; i < currentVotes.length; i++) {
            totalVotes += currentVotes[i];
        }

        if (totalVotes == 0) return; // No votes, no distribution

        uint256 distributed = 0;

        for (uint256 i = 0; i < recipients.length; i++) {
            if (currentVotes[i] > 0) {
                uint256 recipientShare;

                // Last recipient with votes gets remainder to handle rounding
                if (i == recipients.length - 1) {
                    recipientShare = amount - distributed;
                } else {
                    recipientShare = (amount * currentVotes[i]) / totalVotes;
                }

                if (recipientShare > 0) {
                    yieldToken.safeTransfer(recipients[i], recipientShare);
                    distributed += recipientShare;
                }
            }
        }
    }

    /// @notice Updates the voting module
    /// @param _votingModule Address of the voting module
    function setVotingModule(address _votingModule) external onlyOwner {
        if (_votingModule == address(0)) revert ZeroAddress();
        votingModule = IVotingModule(_votingModule);
    }
}