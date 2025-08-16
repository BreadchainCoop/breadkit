// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseDistributionStrategy} from "./BaseDistributionStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title EqualDistributionStrategy
/// @notice Distributes yield equally among all projects
/// @dev Implements equal distribution logic
contract EqualDistributionStrategy is BaseDistributionStrategy {
    using SafeERC20 for IERC20;

    address[] public projects;

    error NoProjects();

    constructor(address _yieldToken) BaseDistributionStrategy(_yieldToken) {}

    /// @dev Distributes amount equally among all projects
    /// @param amount Total amount to distribute
    function _distribute(uint256 amount) internal override {
        if (projects.length == 0) revert NoProjects();

        uint256 amountPerProject = amount / projects.length;
        uint256 distributed = 0;

        for (uint256 i = 0; i < projects.length; i++) {
            uint256 share;

            // Last project gets remainder to handle rounding
            if (i == projects.length - 1) {
                share = amount - distributed;
            } else {
                share = amountPerProject;
            }

            if (share > 0) {
                yieldToken.safeTransfer(projects[i], share);
                distributed += share;
            }
        }
    }

    /// @notice Sets the projects to distribute to
    /// @param _projects Array of project addresses
    function setProjects(address[] calldata _projects) external onlyOwner {
        delete projects;
        for (uint256 i = 0; i < _projects.length; i++) {
            if (_projects[i] == address(0)) revert ZeroAddress();
            projects.push(_projects[i]);
        }
    }

    /// @notice Gets the current projects
    /// @return Array of project addresses
    function getProjects() external view returns (address[] memory) {
        return projects;
    }
}
