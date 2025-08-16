// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/modules/CycleManager.sol";
import "../src/modules/FixedCycleModule.sol";
import "../src/modules/DistributionScheduler.sol";
import "../src/interfaces/ICycleManager.sol";
import "../src/interfaces/ICycleModule.sol";

contract CycleManagerTest is Test {
    CycleManager public cycleManager;
    FixedCycleModule public fixedCycleModule;
    DistributionScheduler public distributionScheduler;
    
    address public owner = address(0x1);
    address public authorized = address(0x2);
    address public unauthorized = address(0x3);
    
    uint256 constant CYCLE_LENGTH = 100;
    uint256 constant MINIMUM_YIELD = 1000;
    uint256 constant MINIMUM_VOTES = 1;
    
    event CycleStarted(uint256 indexed cycleNumber, uint256 startBlock, uint256 endBlock);
    event CycleTransitionValidated(uint256 indexed cycleNumber);
    event CycleModuleSet(address indexed cycleModule);
    event CycleLengthUpdated(uint256 newLength);
    event DistributionScheduled(uint256 indexed cycleNumber, uint256 blockNumber);
    
    function setUp() public {
        vm.startPrank(owner);
        
        cycleManager = new CycleManager();
        fixedCycleModule = new FixedCycleModule();
        distributionScheduler = new DistributionScheduler();
        
        fixedCycleModule.initialize(CYCLE_LENGTH, block.number);
        
        cycleManager.setCycleModule(address(fixedCycleModule));
        
        distributionScheduler.setCycleManager(address(cycleManager));
        distributionScheduler.updateConfig(MINIMUM_YIELD, MINIMUM_VOTES);
        
        vm.stopPrank();
    }
    
    function testInitialState() public view {
        assertEq(cycleManager.getCurrentCycle(), 1);
        assertEq(address(cycleManager.cycleModule()), address(fixedCycleModule));
        assertEq(fixedCycleModule.cycleLength(), CYCLE_LENGTH);
        assertEq(fixedCycleModule.currentCycle(), 1);
    }
    
    function testSetCycleModule() public {
        vm.startPrank(owner);
        
        FixedCycleModule newModule = new FixedCycleModule();
        newModule.initialize(200, block.number);
        
        vm.expectEmit(true, false, false, true);
        emit CycleModuleSet(address(newModule));
        
        cycleManager.setCycleModule(address(newModule));
        assertEq(address(cycleManager.cycleModule()), address(newModule));
        
        vm.stopPrank();
    }
    
    function testSetCycleModuleUnauthorized() public {
        vm.startPrank(unauthorized);
        
        FixedCycleModule newModule = new FixedCycleModule();
        vm.expectRevert();
        cycleManager.setCycleModule(address(newModule));
        
        vm.stopPrank();
    }
    
    function testIsDistributionReady() public {
        assertFalse(cycleManager.isDistributionReady(1, 2000, MINIMUM_YIELD));
        
        vm.roll(block.number + CYCLE_LENGTH);
        
        assertTrue(cycleManager.isDistributionReady(1, 2000, MINIMUM_YIELD));
        
        assertFalse(cycleManager.isDistributionReady(0, 2000, MINIMUM_YIELD));
        
        assertFalse(cycleManager.isDistributionReady(1, 500, MINIMUM_YIELD));
    }
    
    function testStartNewCycle() public {
        vm.roll(block.number + CYCLE_LENGTH);
        
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, true);
        emit CycleTransitionValidated(2);
        
        cycleManager.startNewCycle();
        
        assertEq(cycleManager.getCurrentCycle(), 2);
        
        vm.stopPrank();
    }
    
    function testStartNewCycleNotReady() public {
        vm.startPrank(owner);
        
        vm.expectRevert("Cycle transition invalid");
        cycleManager.startNewCycle();
        
        vm.stopPrank();
    }
    
    function testGetCycleInfo() public {
        ICycleManager.CycleInfo memory info = cycleManager.getCycleInfo();
        
        assertEq(info.cycleNumber, 1);
        assertEq(info.blocksRemaining, CYCLE_LENGTH);
        assertTrue(info.isActive);
        
        vm.roll(block.number + CYCLE_LENGTH + 1);
        
        info = cycleManager.getCycleInfo();
        assertEq(info.blocksRemaining, 0);
        assertFalse(info.isActive);
    }
    
    function testGetCycleProgress() public {
        assertEq(cycleManager.getCycleProgress(), 0);
        
        vm.roll(block.number + 50);
        assertEq(cycleManager.getCycleProgress(), 50);
        
        vm.roll(block.number + 50);
        assertEq(cycleManager.getCycleProgress(), 100);
        
        vm.roll(block.number + 50);
        assertEq(cycleManager.getCycleProgress(), 100);
    }
    
    function testGetBlocksUntilNextCycle() public {
        assertEq(cycleManager.getBlocksUntilNextCycle(), CYCLE_LENGTH);
        
        vm.roll(block.number + 25);
        assertEq(cycleManager.getBlocksUntilNextCycle(), 75);
        
        vm.roll(block.number + 75);
        assertEq(cycleManager.getBlocksUntilNextCycle(), 0);
    }
    
    function testUpdateCycleLength() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, true);
        emit CycleLengthUpdated(200);
        
        fixedCycleModule.updateCycleLength(200);
        assertEq(fixedCycleModule.cycleLength(), 200);
        
        vm.stopPrank();
    }
    
    function testDistributionScheduler() public {
        (bool canDistribute, string memory reason) = distributionScheduler.checkDistributionConditions(1, 2000);
        assertFalse(canDistribute);
        assertEq(reason, "Cycle not complete");
        
        vm.roll(block.number + CYCLE_LENGTH);
        
        (canDistribute, reason) = distributionScheduler.checkDistributionConditions(1, 2000);
        assertTrue(canDistribute);
        assertEq(reason, "Ready for distribution");
        
        (canDistribute, reason) = distributionScheduler.checkDistributionConditions(0, 2000);
        assertFalse(canDistribute);
        assertEq(reason, "Insufficient votes");
        
        (canDistribute, reason) = distributionScheduler.checkDistributionConditions(1, 500);
        assertFalse(canDistribute);
        assertEq(reason, "Insufficient yield");
    }
    
    function testScheduleDistribution() public {
        vm.roll(block.number + CYCLE_LENGTH);
        
        vm.expectEmit(true, false, false, true);
        emit DistributionScheduled(1, block.number);
        
        bool scheduled = distributionScheduler.scheduleDistribution(1, 2000);
        assertTrue(scheduled);
        
        DistributionScheduler.DistributionRecord memory record = distributionScheduler.getDistributionHistory(1);
        assertEq(record.cycleNumber, 1);
        assertEq(record.totalYield, 2000);
        assertEq(record.totalVotes, 1);
        assertFalse(record.executed);
    }
    
    function testMarkDistributionExecuted() public {
        vm.roll(block.number + CYCLE_LENGTH);
        distributionScheduler.scheduleDistribution(1, 2000);
        
        vm.prank(owner);
        distributionScheduler.markDistributionExecuted(1);
        
        DistributionScheduler.DistributionRecord memory record = distributionScheduler.getDistributionHistory(1);
        assertTrue(record.executed);
    }
    
    function testMultipleCycleTransitions() public {
        uint256 startBlock = block.number;
        
        for (uint256 i = 1; i <= 3; i++) {
            vm.roll(startBlock + (CYCLE_LENGTH * i));
            
            assertTrue(cycleManager.isDistributionReady(1, 2000, MINIMUM_YIELD));
            
            vm.prank(owner);
            cycleManager.startNewCycle();
            
            assertEq(cycleManager.getCurrentCycle(), i + 1);
        }
    }
    
    function testCycleModuleNotSet() public {
        CycleManager newManager = new CycleManager();
        
        vm.expectRevert("Cycle module not set");
        newManager.getCurrentCycle();
        
        vm.expectRevert("Cycle module not set");
        newManager.isDistributionReady(1, 2000, MINIMUM_YIELD);
        
        vm.expectRevert("Cycle module not set");
        newManager.getCycleInfo();
    }
    
    function testValidateScheduleConfig() public {
        DistributionScheduler.ScheduleConfig memory config;
        
        config = DistributionScheduler.ScheduleConfig({
            minimumYield: 1000,
            minimumVotes: 1,
            requireVotes: true,
            requireYield: true
        });
        assertTrue(distributionScheduler.validateSchedule(config));
        
        config = DistributionScheduler.ScheduleConfig({
            minimumYield: 0,
            minimumVotes: 1,
            requireVotes: true,
            requireYield: true
        });
        assertFalse(distributionScheduler.validateSchedule(config));
        
        config = DistributionScheduler.ScheduleConfig({
            minimumYield: 1000,
            minimumVotes: 0,
            requireVotes: true,
            requireYield: true
        });
        assertFalse(distributionScheduler.validateSchedule(config));
    }
    
    function testGetNextDistributionEstimate() public {
        (uint256 blocksRemaining, uint256 estimatedBlock) = distributionScheduler.getNextDistributionEstimate();
        assertEq(blocksRemaining, CYCLE_LENGTH);
        assertEq(estimatedBlock, block.number + CYCLE_LENGTH);
        
        vm.roll(block.number + 50);
        
        (blocksRemaining, estimatedBlock) = distributionScheduler.getNextDistributionEstimate();
        assertEq(blocksRemaining, 50);
    }
}