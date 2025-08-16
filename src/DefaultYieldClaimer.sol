// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@solady/contracts/auth/Ownable.sol";

contract DefaultYieldClaimer is Ownable {
    error InvalidVotingToken();
    error InvalidInitialProjects();

    address public votingToken;
    address[] public recipients;
    uint256 public percentVoted;

    constructor(address votingToken_, address[] memory initialRecipients_, uint256 percentVoted_, address owner_) {
        if (votingToken_ == address(0)) revert InvalidVotingToken();
        if (initialRecipients_.length == 0) revert InvalidInitialProjects();

        votingToken = votingToken_;
        recipients = initialRecipients_;
        percentVoted = percentVoted_;

        _initializeOwner(owner_);
    }

    // TODO: add default voting logic
}
