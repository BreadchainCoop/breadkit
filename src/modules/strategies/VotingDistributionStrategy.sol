// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseDistributionStrategy} from "./BaseDistributionStrategy.sol";
import {IVotingModule} from "../../interfaces/IVotingModule.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title VotingDistributionStrategy
/// @notice Distributes yield based on voting results
/// @dev Implements proportional distribution based on vote counts
contract VotingDistributionStrategy is BaseDistributionStrategy {
    using SafeERC20 for IERC20;

    IVotingModule public votingModule;
    address[] public projects;
    mapping(address => uint256) public projectIndex;

    error InvalidVotesLength();
    error NoProjects();

    constructor(address _yieldToken, address _votingModule) BaseDistributionStrategy(_yieldToken) {
        if (_votingModule == address(0)) revert ZeroAddress();
        votingModule = IVotingModule(_votingModule);
    }

    /// @dev Distributes amount based on voting weights
    /// @param amount Total amount to distribute
    function _distribute(uint256 amount) internal override {
        if (projects.length == 0) revert NoProjects();

        uint256[] memory currentVotes = votingModule.getCurrentVotingDistribution();
        if (currentVotes.length != projects.length) revert InvalidVotesLength();

        uint256 totalVotes = 0;
        for (uint256 i = 0; i < currentVotes.length; i++) {
            totalVotes += currentVotes[i];
        }

        if (totalVotes == 0) return; // No votes, no distribution

        uint256 distributed = 0;

        for (uint256 i = 0; i < projects.length; i++) {
            if (currentVotes[i] > 0) {
                uint256 projectShare;

                // Last project with votes gets remainder to handle rounding
                if (i == projects.length - 1) {
                    projectShare = amount - distributed;
                } else {
                    projectShare = (amount * currentVotes[i]) / totalVotes;
                }

                if (projectShare > 0) {
                    yieldToken.safeTransfer(projects[i], projectShare);
                    distributed += projectShare;
                }
            }
        }
    }

    /// @notice Sets the projects to distribute to based on voting
    /// @param _projects Array of project addresses
    function setProjects(address[] calldata _projects) external onlyOwner {
        delete projects;
        for (uint256 i = 0; i < _projects.length; i++) {
            if (_projects[i] == address(0)) revert ZeroAddress();
            projects.push(_projects[i]);
            projectIndex[_projects[i]] = i;
        }
    }

    /// @notice Updates the voting module
    /// @param _votingModule Address of the voting module
    function setVotingModule(address _votingModule) external onlyOwner {
        if (_votingModule == address(0)) revert ZeroAddress();
        votingModule = IVotingModule(_votingModule);
    }

    /// @notice Gets the current projects
    /// @return Array of project addresses
    function getProjects() external view returns (address[] memory) {
        return projects;
    }
}
