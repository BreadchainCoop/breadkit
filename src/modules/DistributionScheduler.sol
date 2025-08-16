// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICycleManager} from "../interfaces/ICycleManager.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

contract DistributionScheduler is Ownable {
    ICycleManager public cycleManager;
    uint256 public minimumYield;
    uint256 public minimumVotes;
    
    mapping(uint256 => DistributionRecord) public distributionHistory;
    
    struct DistributionRecord {
        uint256 cycleNumber;
        uint256 blockNumber;
        uint256 timestamp;
        uint256 totalYield;
        uint256 totalVotes;
        bool executed;
    }
    
    struct ScheduleConfig {
        uint256 minimumYield;
        uint256 minimumVotes;
        bool requireVotes;
        bool requireYield;
    }
    
    event DistributionScheduled(uint256 indexed cycleNumber, uint256 blockNumber);
    event DistributionExecuted(uint256 indexed cycleNumber, uint256 totalYield, uint256 totalVotes);
    event ConfigUpdated(uint256 minimumYield, uint256 minimumVotes);
    event CycleManagerSet(address indexed cycleManager);
    
    constructor() {
        _initializeOwner(msg.sender);
    }
    
    function setCycleManager(address _cycleManager) external onlyOwner {
        require(_cycleManager != address(0), "Invalid cycle manager");
        cycleManager = ICycleManager(_cycleManager);
        emit CycleManagerSet(_cycleManager);
    }
    
    function updateConfig(uint256 _minimumYield, uint256 _minimumVotes) external onlyOwner {
        minimumYield = _minimumYield;
        minimumVotes = _minimumVotes;
        emit ConfigUpdated(_minimumYield, _minimumVotes);
    }
    
    function checkDistributionConditions(
        uint256 votesCast,
        uint256 availableYield
    ) external view returns (bool canDistribute, string memory reason) {
        require(address(cycleManager) != address(0), "Cycle manager not set");
        
        if (!cycleManager.isDistributionReady(votesCast, availableYield, minimumYield)) {
            ICycleManager.CycleInfo memory info = cycleManager.getCycleInfo();
            
            if (info.blocksRemaining > 0) {
                return (false, "Cycle not complete");
            }
            
            if (votesCast < minimumVotes) {
                return (false, "Insufficient votes");
            }
            
            if (availableYield < minimumYield) {
                return (false, "Insufficient yield");
            }
            
            return (false, "Distribution not ready");
        }
        
        return (true, "Ready for distribution");
    }
    
    function scheduleDistribution(
        uint256 votesCast,
        uint256 availableYield
    ) external returns (bool) {
        require(address(cycleManager) != address(0), "Cycle manager not set");
        
        (bool canDistribute,) = this.checkDistributionConditions(votesCast, availableYield);
        require(canDistribute, "Distribution conditions not met");
        
        uint256 currentCycle = cycleManager.getCurrentCycle();
        require(!distributionHistory[currentCycle].executed, "Distribution already executed");
        
        distributionHistory[currentCycle] = DistributionRecord({
            cycleNumber: currentCycle,
            blockNumber: block.number,
            timestamp: block.timestamp,
            totalYield: availableYield,
            totalVotes: votesCast,
            executed: false
        });
        
        emit DistributionScheduled(currentCycle, block.number);
        return true;
    }
    
    function markDistributionExecuted(uint256 cycleNumber) external {
        require(msg.sender == owner() || msg.sender == address(cycleManager), "Not authorized");
        require(distributionHistory[cycleNumber].blockNumber > 0, "Distribution not scheduled");
        require(!distributionHistory[cycleNumber].executed, "Already executed");
        
        distributionHistory[cycleNumber].executed = true;
        
        emit DistributionExecuted(
            cycleNumber,
            distributionHistory[cycleNumber].totalYield,
            distributionHistory[cycleNumber].totalVotes
        );
    }
    
    function getDistributionHistory(uint256 cycleNumber) external view returns (DistributionRecord memory) {
        return distributionHistory[cycleNumber];
    }
    
    function getNextDistributionEstimate() external view returns (uint256 blocksRemaining, uint256 estimatedBlock) {
        require(address(cycleManager) != address(0), "Cycle manager not set");
        
        ICycleManager.CycleInfo memory info = cycleManager.getCycleInfo();
        return (info.blocksRemaining, info.endBlock);
    }
    
    function validateSchedule(ScheduleConfig memory config) external pure returns (bool) {
        if (config.requireYield && config.minimumYield == 0) {
            return false;
        }
        if (config.requireVotes && config.minimumVotes == 0) {
            return false;
        }
        return true;
    }
}