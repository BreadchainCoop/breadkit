// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingModule} from "../interfaces/IVotingModule.sol";
import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";

/// @title MockVotingModule
/// @notice Mock implementation of IVotingModule for testing
/// @dev Returns configurable voting power and distribution values
contract MockVotingModule is IVotingModule {
    uint256 public totalCurrentVotingPower;
    uint256[] public votingDistribution;
    mapping(address => uint256) public votingPower;
    mapping(address => address) public delegates;
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    uint256 public maxPoints = 100;
    bytes32 public constant DOMAIN_SEPARATOR = keccak256("MockVotingModule");
    IVotingPowerStrategy[] public votingStrategies;

    /// @notice Sets the total current voting power for testing
    /// @param _totalPower The total voting power to set
    function setTotalCurrentVotingPower(uint256 _totalPower) external {
        totalCurrentVotingPower = _totalPower;
    }

    /// @notice Sets the voting distribution for testing
    /// @param _distribution Array of vote counts per project
    function setVotingDistribution(uint256[] calldata _distribution) external {
        votingDistribution = _distribution;
    }

    /// @notice Sets voting power for a specific account
    /// @param account The account to set voting power for
    /// @param power The voting power to set
    function setVotingPower(address account, uint256 power) external {
        votingPower[account] = power;
    }

    /// @inheritdoc IVotingModule
    function vote(uint256[] calldata points) external override {
        // Mock implementation - just store the points
        votingDistribution = points;
    }

    /// @inheritdoc IVotingModule
    function voteWithMultipliers(uint256[] calldata points, uint256[] calldata) external override {
        // Mock implementation - ignore multipliers
        votingDistribution = points;
    }

    /// @inheritdoc IVotingModule
    function delegate(address delegatee) external override {
        delegates[msg.sender] = delegatee;
    }

    /// @inheritdoc IVotingModule
    function getVotingPower(address account) external view override returns (uint256) {
        return votingPower[account];
    }

    /// @inheritdoc IVotingModule
    function castVote(uint256[] calldata points) external override {
        votingDistribution = points;
    }

    /// @inheritdoc IVotingModule
    function castVoteWithMultipliers(uint256[] calldata points, uint256[] calldata) external override {
        votingDistribution = points;
    }

    /// @inheritdoc IVotingModule
    function getCurrentVotingDistribution() external view override returns (uint256[] memory) {
        // If no distribution set, return array with totalCurrentVotingPower as single element
        if (votingDistribution.length == 0 && totalCurrentVotingPower > 0) {
            uint256[] memory dist = new uint256[](1);
            dist[0] = totalCurrentVotingPower;
            return dist;
        }
        return votingDistribution;
    }

    /// @inheritdoc IVotingModule
    function setMaxPoints(uint256 _maxPoints) external override {
        maxPoints = _maxPoints;
    }

    /// @inheritdoc IVotingModule
    function castVoteWithSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata)
        external
        override
    {
        require(!usedNonces[voter][nonce], "Nonce already used");
        usedNonces[voter][nonce] = true;
        votingDistribution = points;
    }

    /// @inheritdoc IVotingModule
    function castBatchVotesWithSignature(
        address[] calldata voters,
        uint256[][] calldata points,
        uint256[] calldata nonces,
        bytes[] calldata
    ) external override {
        require(voters.length == points.length, "Length mismatch");
        require(voters.length == nonces.length, "Length mismatch");

        // Just use the last vote for simplicity
        if (points.length > 0) {
            votingDistribution = points[points.length - 1];
            for (uint256 i = 0; i < voters.length; i++) {
                usedNonces[voters[i]][nonces[i]] = true;
            }
        }
    }

    /// @inheritdoc IVotingModule
    function validateVotePoints(uint256[] calldata points) external view override returns (bool) {
        uint256 total = 0;
        for (uint256 i = 0; i < points.length; i++) {
            total += points[i];
        }
        return total <= maxPoints;
    }

    /// @inheritdoc IVotingModule
    function validateSignature(address, uint256[] calldata, uint256, bytes calldata)
        external
        pure
        override
        returns (bool)
    {
        // Always return true for mock
        return true;
    }

    /// @inheritdoc IVotingModule
    function isNonceUsed(address voter, uint256 nonce) external view override returns (bool) {
        return usedNonces[voter][nonce];
    }

    /// @inheritdoc IVotingModule
    function getVotingPowerStrategies() external view override returns (IVotingPowerStrategy[] memory) {
        return votingStrategies;
    }

    /// @notice Adds a voting power strategy for testing
    /// @param strategy The strategy to add
    function addVotingPowerStrategy(IVotingPowerStrategy strategy) external {
        votingStrategies.push(strategy);
    }
}
