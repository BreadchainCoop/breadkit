// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICycleModule} from "../interfaces/ICycleModule.sol";
import {ICycleManager} from "../interfaces/ICycleManager.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

contract FixedCycleModule is ICycleModule, Ownable {
    uint256 public cycleLength;
    uint256 public currentCycle;
    uint256 public lastCycleStartBlock;
    bool public initialized;

    modifier onlyInitialized() {
        require(initialized, "Not initialized");
        _;
    }

    constructor() {
        _initializeOwner(msg.sender);
    }

    function initialize(uint256 _cycleLength, uint256 _startBlock) external override onlyOwner {
        require(!initialized, "Already initialized");
        require(_cycleLength > 0, "Invalid cycle length");
        
        cycleLength = _cycleLength;
        lastCycleStartBlock = _startBlock > 0 ? _startBlock : block.number;
        currentCycle = 1;
        initialized = true;
        
        emit CycleInitialized(_cycleLength, lastCycleStartBlock);
    }

    function getCurrentCycle() external view override onlyInitialized returns (uint256) {
        return currentCycle;
    }

    function isDistributionReady() external view override onlyInitialized returns (bool) {
        return block.number >= lastCycleStartBlock + cycleLength;
    }

    function startNewCycle() external override onlyInitialized {
        require(this.isDistributionReady(), "Cycle not complete");
        
        currentCycle++;
        lastCycleStartBlock = block.number;
        
        emit CycleStarted(currentCycle, lastCycleStartBlock, lastCycleStartBlock + cycleLength);
    }

    function getCycleInfo() external view override onlyInitialized returns (ICycleManager.CycleInfo memory) {
        uint256 endBlock = lastCycleStartBlock + cycleLength;
        uint256 blocksRemaining = endBlock > block.number ? endBlock - block.number : 0;
        
        return ICycleManager.CycleInfo({
            cycleNumber: currentCycle,
            startBlock: lastCycleStartBlock,
            endBlock: endBlock,
            blocksRemaining: blocksRemaining,
            isActive: blocksRemaining > 0
        });
    }

    function getBlocksUntilNextCycle() external view override onlyInitialized returns (uint256) {
        uint256 endBlock = lastCycleStartBlock + cycleLength;
        return endBlock > block.number ? endBlock - block.number : 0;
    }

    function getCycleProgress() external view override onlyInitialized returns (uint256) {
        uint256 blocksElapsed = block.number - lastCycleStartBlock;
        if (blocksElapsed >= cycleLength) {
            return 100;
        }
        return (blocksElapsed * 100) / cycleLength;
    }

    function updateCycleLength(uint256 _newCycleLength) external override onlyOwner onlyInitialized {
        require(_newCycleLength > 0, "Invalid cycle length");
        cycleLength = _newCycleLength;
        emit CycleLengthUpdated(_newCycleLength);
    }

    event CycleStarted(uint256 indexed cycleNumber, uint256 startBlock, uint256 endBlock);
}