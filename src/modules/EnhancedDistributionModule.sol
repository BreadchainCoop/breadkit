// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionModule} from "../interfaces/IDistributionModule.sol";
import {IDistributionStrategyModule} from "../interfaces/IDistributionStrategyModule.sol";
import {IVotingModule} from "../interfaces/IVotingModule.sol";
import {IAMMVotingPowerModule} from "../interfaces/IAMMVotingPowerModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title EnhancedDistributionModule
/// @notice Enhanced distribution module that integrates strategy-based distribution
/// @dev Manages yield distribution using both fixed strategy and voting-based allocation
contract EnhancedDistributionModule is IDistributionModule, Ownable {
    using SafeERC20 for IERC20;

    error InvalidCycleLength();
    error InvalidDivisor();
    error ZeroAddress();
    error DistributionNotReady();
    error NoProjectsConfigured();
    error InsufficientYield();

    uint256 public cycleLength;
    uint256 public yieldFixedSplitDivisor;
    uint256 public lastDistributionTime;
    bool public paused;

    IDistributionStrategyModule public strategyModule;
    IVotingModule public votingModule;
    IAMMVotingPowerModule public ammVotingPower;
    IERC20 public yieldToken;

    address[] public projects;
    mapping(address => bool) public isProject;
    mapping(address => uint256) public projectIndex;

    uint256[] public currentDistribution;
    uint256 public totalVotes;

    event ProjectAdded(address indexed project);
    event ProjectRemoved(address indexed project);
    event CycleLengthUpdated(uint256 newLength);
    event YieldFixedSplitDivisorUpdated(uint256 newDivisor);
    event AMMVotingPowerUpdated(address newAMMVotingPower);

    constructor(address _yieldToken, address _strategyModule, uint256 _cycleLength, uint256 _yieldFixedSplitDivisor) {
        if (_yieldToken == address(0)) revert ZeroAddress();
        if (_strategyModule == address(0)) revert ZeroAddress();
        if (_cycleLength == 0) revert InvalidCycleLength();
        if (_yieldFixedSplitDivisor == 0) revert InvalidDivisor();

        yieldToken = IERC20(_yieldToken);
        strategyModule = IDistributionStrategyModule(_strategyModule);
        cycleLength = _cycleLength;
        yieldFixedSplitDivisor = _yieldFixedSplitDivisor;
        lastDistributionTime = block.timestamp;

        _initializeOwner(msg.sender);
    }

    /// @inheritdoc IDistributionModule
    function distributeYield() external override {
        require(!paused, "Distribution is paused");
        if (block.timestamp < lastDistributionTime + cycleLength) {
            revert DistributionNotReady();
        }
        if (projects.length == 0) revert NoProjectsConfigured();

        uint256 totalYield = yieldToken.balanceOf(address(this));
        if (totalYield == 0) revert InsufficientYield();

        (uint256 fixedAmount, uint256 votedAmount) = strategyModule.calculateSplit(totalYield);

        if (fixedAmount > 0 && projects.length > 0) {
            _distributeFixedPortion(fixedAmount);
        }

        if (votedAmount > 0 && totalVotes > 0) {
            _distributeVotedPortion(votedAmount);
        }

        lastDistributionTime = block.timestamp;

        // Prepare arrays for event
        uint256[] memory votedDistributions = new uint256[](projects.length);
        uint256[] memory fixedDistributions = new uint256[](projects.length);
        
        // Populate distribution arrays
        for (uint256 i = 0; i < projects.length; i++) {
            fixedDistributions[i] = fixedAmount / projects.length;
            if (i == projects.length - 1) {
                fixedDistributions[i] = fixedAmount - (fixedAmount / projects.length * (projects.length - 1));
            }
            if (totalVotes > 0 && currentDistribution[i] > 0) {
                votedDistributions[i] = (votedAmount * currentDistribution[i]) / totalVotes;
            }
        }
        
        emit YieldDistributed(totalYield, totalVotes, projects, votedDistributions, fixedDistributions);
        emit CycleCompleted(block.number / cycleLength, block.number);
    }

    /// @dev Distributes the fixed portion equally among all projects
    /// @param fixedAmount Amount to distribute equally
    function _distributeFixedPortion(uint256 fixedAmount) internal {
        uint256 amountPerProject = fixedAmount / projects.length;
        uint256 distributed = 0;

        for (uint256 i = 0; i < projects.length; i++) {
            uint256 projectShare;

            // Last project gets remainder to handle rounding
            if (i == projects.length - 1) {
                projectShare = fixedAmount - distributed;
            } else {
                projectShare = amountPerProject;
                distributed += projectShare;
            }

            if (projectShare > 0) {
                yieldToken.safeTransfer(projects[i], projectShare);
            }
        }
    }

    /// @dev Distributes the voted portion based on current voting results
    /// @param votedAmount Amount to distribute based on votes
    function _distributeVotedPortion(uint256 votedAmount) internal {
        uint256 distributed = 0;

        for (uint256 i = 0; i < projects.length; i++) {
            if (currentDistribution[i] > 0) {
                uint256 projectShare;

                if (i == projects.length - 1) {
                    projectShare = votedAmount - distributed;
                } else {
                    projectShare = (votedAmount * currentDistribution[i]) / totalVotes;
                    distributed += projectShare;
                }

                if (projectShare > 0) {
                    yieldToken.safeTransfer(projects[i], projectShare);
                }
            }
        }
    }

    /// @inheritdoc IDistributionModule
    function getCurrentDistributionState() external view override returns (IDistributionModule.DistributionState memory state) {
        uint256 totalYield = yieldToken.balanceOf(address(this));
        (uint256 fixedAmount, uint256 votedAmount) = strategyModule.calculateSplit(totalYield);
        
        uint256[] memory votedDistributions = new uint256[](projects.length);
        uint256[] memory fixedDistributions = new uint256[](projects.length);
        
        for (uint256 i = 0; i < projects.length; i++) {
            fixedDistributions[i] = fixedAmount / projects.length;
            if (i == projects.length - 1) {
                fixedDistributions[i] = fixedAmount - (fixedAmount / projects.length * (projects.length - 1));
            }
            if (totalVotes > 0 && currentDistribution[i] > 0) {
                votedDistributions[i] = (votedAmount * currentDistribution[i]) / totalVotes;
            }
        }
        
        state = IDistributionModule.DistributionState({
            totalYield: totalYield,
            fixedAmount: fixedAmount,
            votedAmount: votedAmount,
            totalVotes: totalVotes,
            lastDistributionBlock: lastDistributionTime,
            cycleNumber: block.number / cycleLength,
            recipients: projects,
            votedDistributions: votedDistributions,
            fixedDistributions: fixedDistributions
        });
    }

    /// @inheritdoc IDistributionModule
    function validateDistribution() external view override returns (bool canDistribute, string memory reason) {
        if (paused) {
            return (false, "Distribution is paused");
        }
        if (block.timestamp < lastDistributionTime + cycleLength) {
            return (false, "Distribution not ready");
        }
        if (projects.length == 0) {
            return (false, "No projects configured");
        }
        uint256 totalYield = yieldToken.balanceOf(address(this));
        if (totalYield == 0) {
            return (false, "Insufficient yield");
        }
        return (true, "");
    }

    /// @inheritdoc IDistributionModule
    function emergencyPause() external override onlyOwner {
        paused = true;
        emit EmergencyPause(msg.sender, block.timestamp);
    }

    /// @inheritdoc IDistributionModule
    function emergencyResume() external override onlyOwner {
        paused = false;
    }

    /// @inheritdoc IDistributionModule
    function setCycleLength(uint256 _cycleLength) external override onlyOwner {
        if (_cycleLength == 0) revert InvalidCycleLength();
        cycleLength = _cycleLength;
        emit CycleLengthUpdated(_cycleLength);
    }

    /// @inheritdoc IDistributionModule
    function setYieldFixedSplitDivisor(uint256 _yieldFixedSplitDivisor) external override onlyOwner {
        if (_yieldFixedSplitDivisor == 0) revert InvalidDivisor();
        yieldFixedSplitDivisor = _yieldFixedSplitDivisor;

        if (address(strategyModule) != address(0)) {
            strategyModule.updateSplitRatio(_yieldFixedSplitDivisor);
        }

        emit YieldFixedSplitDivisorUpdated(_yieldFixedSplitDivisor);
    }

    /// @notice Sets the AMM voting power module
    /// @param _ammVotingPower Address of the AMM voting power module
    function setAMMVotingPower(address _ammVotingPower) external onlyOwner {
        if (_ammVotingPower == address(0)) revert ZeroAddress();
        ammVotingPower = IAMMVotingPowerModule(_ammVotingPower);
        emit AMMVotingPowerUpdated(_ammVotingPower);
    }

    /// @notice Sets the voting module for vote-based distribution
    /// @param _votingModule Address of the voting module
    function setVotingModule(address _votingModule) external onlyOwner {
        if (_votingModule == address(0)) revert ZeroAddress();
        votingModule = IVotingModule(_votingModule);
    }

    /// @notice Sets the strategy module for fixed distribution
    /// @param _strategyModule Address of the strategy module
    function setStrategyModule(address _strategyModule) external onlyOwner {
        if (_strategyModule == address(0)) revert ZeroAddress();
        strategyModule = IDistributionStrategyModule(_strategyModule);
        strategyModule.updateSplitRatio(yieldFixedSplitDivisor);
    }

    /// @notice Adds a project to receive distributions
    /// @param project Address of the project
    function addProject(address project) external onlyOwner {
        if (project == address(0)) revert ZeroAddress();
        if (isProject[project]) return;

        projects.push(project);
        isProject[project] = true;
        projectIndex[project] = projects.length - 1;
        currentDistribution.push(0);

        emit ProjectAdded(project);
    }

    /// @notice Removes a project from distributions
    /// @param project Address of the project to remove
    function removeProject(address project) external onlyOwner {
        if (!isProject[project]) return;

        uint256 index = projectIndex[project];
        uint256 lastIndex = projects.length - 1;

        if (index != lastIndex) {
            projects[index] = projects[lastIndex];
            projectIndex[projects[lastIndex]] = index;
            currentDistribution[index] = currentDistribution[lastIndex];
        }

        projects.pop();
        currentDistribution.pop();
        delete isProject[project];
        delete projectIndex[project];

        emit ProjectRemoved(project);
    }

    /// @notice Updates the distribution based on current votes
    /// @param votes Array of vote counts for each project
    function updateDistribution(uint256[] calldata votes) external onlyOwner {
        require(votes.length == projects.length, "Invalid votes length");

        uint256 newTotalVotes = 0;
        for (uint256 i = 0; i < votes.length; i++) {
            currentDistribution[i] = votes[i];
            newTotalVotes += votes[i];
        }

        totalVotes = newTotalVotes;
    }

    /// @notice Gets the list of all projects
    /// @return Array of project addresses
    function getProjects() external view returns (address[] memory) {
        return projects;
    }

    /// @notice Checks if distribution is ready
    /// @return True if enough time has passed since last distribution
    function isDistributionReady() external view returns (bool) {
        return block.timestamp >= lastDistributionTime + cycleLength;
    }

    /// @notice Gets time until next distribution
    /// @return Seconds until next distribution is ready
    function timeUntilNextDistribution() external view returns (uint256) {
        uint256 nextDistributionTime = lastDistributionTime + cycleLength;
        if (block.timestamp >= nextDistributionTime) {
            return 0;
        }
        return nextDistributionTime - block.timestamp;
    }
}