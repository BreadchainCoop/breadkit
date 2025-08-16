// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingModule} from "../../src/interfaces/IVotingModule.sol";

contract MockVotingModule is IVotingModule {
    uint256[] public votingDistribution;
    mapping(address => uint256) public votingPower;
    mapping(address => address) public delegates;
    
    function setVotes(uint256[] memory votes) external {
        votingDistribution = votes;
    }
    
    function vote(uint256[] calldata points) external override {}
    
    function voteWithMultipliers(uint256[] calldata points, uint256[] calldata multiplierIndices) external override {}
    
    function delegate(address delegatee) external override {
        delegates[msg.sender] = delegatee;
    }
    
    function getVotingPower(address account) external view override returns (uint256) {
        return votingPower[account];
    }
    
    function getVotingPowerForPeriod(address account, uint256, uint256) external view override returns (uint256) {
        return votingPower[account];
    }
    
    function getCurrentAccumulatedVotingPower(address account) external view override returns (uint256) {
        return votingPower[account];
    }
    
    function castVote(uint256[] calldata points) external override {}
    
    function castVoteWithMultipliers(uint256[] calldata points, uint256[] calldata multiplierIndices) external override {}
    
    function getCurrentVotingDistribution() external view override returns (uint256[] memory) {
        return votingDistribution;
    }
    
    function setMinRequiredVotingPower(uint256) external override {}
    
    function setMaxPoints(uint256) external override {}
    
    function setVotingPower(address account, uint256 power) external {
        votingPower[account] = power;
    }
}