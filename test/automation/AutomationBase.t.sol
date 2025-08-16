// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/modules/automation/ChainlinkAutomation.sol";
import "../../src/modules/automation/GelatoAutomation.sol";
import "../../src/mocks/MockCycleManager.sol";
import "../../src/interfaces/IDistributionModule.sol";

contract MockDistributionModule is IDistributionModule {
    uint256 public distributeCallCount;

    function distribute() external {
        distributeCallCount++;
    }

    function getCurrentDistribution() external pure returns (uint256[] memory) {
        uint256[] memory dist = new uint256[](3);
        dist[0] = 40;
        dist[1] = 35;
        dist[2] = 25;
        return dist;
    }

    function setCycleLength(uint256) external {}
    function setYieldFixedSplitDivisor(uint256) external {}
    function setAMMVotingPower(address) external {}
}

contract AutomationBaseTest is Test {
    ChainlinkAutomation public chainlinkAutomation;
    GelatoAutomation public gelatoAutomation;
    MockCycleManager public cycleManager;
    MockDistributionModule public distributionModule;

    address public chainlinkKeeper = address(0x1);
    address public gelatoExecutor = address(0x2);

    event AutomationExecuted(address indexed executor, uint256 blockNumber);
    event DistributionExecuted(uint256 blockNumber, uint256 yield, uint256 votes);

    function setUp() public {
        // Deploy mock distribution module
        distributionModule = new MockDistributionModule();

        // Deploy cycle manager with distribution logic
        cycleManager = new MockCycleManager(address(distributionModule), 100);

        // Deploy automation implementations
        chainlinkAutomation = new ChainlinkAutomation(address(cycleManager));
        gelatoAutomation = new GelatoAutomation(address(cycleManager));

        // Setup initial state
        cycleManager.setCurrentVotes(100);
        cycleManager.setAvailableYield(2000);
    }

    function testChainlinkCheckUpkeep() public {
        // Initially should not need upkeep (too soon)
        (bool upkeepNeeded, bytes memory performData) = chainlinkAutomation.checkUpkeep("");
        assertFalse(upkeepNeeded);

        // Advance blocks
        vm.roll(block.number + 101);

        // Now should need upkeep
        (upkeepNeeded, performData) = chainlinkAutomation.checkUpkeep("");
        assertTrue(upkeepNeeded);
        assertGt(performData.length, 0);
    }

    function testChainlinkPerformUpkeep() public {
        // Advance blocks to make distribution ready
        vm.roll(block.number + 101);

        // Check upkeep
        (bool upkeepNeeded,) = chainlinkAutomation.checkUpkeep("");
        assertTrue(upkeepNeeded);

        // Perform upkeep
        vm.expectEmit(true, false, false, true);
        emit AutomationExecuted(chainlinkKeeper, block.number);

        vm.prank(chainlinkKeeper);
        chainlinkAutomation.performUpkeep("");

        // Verify distribution was called
        assertEq(distributionModule.distributeCallCount(), 1);
        assertEq(cycleManager.currentCycleNumber(), 2);
    }

    function testGelatoChecker() public {
        // Initially should not be executable (too soon)
        (bool canExec, bytes memory execPayload) = gelatoAutomation.checker();
        assertFalse(canExec);

        // Advance blocks
        vm.roll(block.number + 101);

        // Now should be executable
        (canExec, execPayload) = gelatoAutomation.checker();
        assertTrue(canExec);
        assertGt(execPayload.length, 0);
    }

    function testGelatoExecute() public {
        // Advance blocks to make distribution ready
        vm.roll(block.number + 101);

        // Check if executable
        (bool canExec,) = gelatoAutomation.checker();
        assertTrue(canExec);

        // Execute
        vm.expectEmit(true, false, false, true);
        emit AutomationExecuted(gelatoExecutor, block.number);

        vm.prank(gelatoExecutor);
        gelatoAutomation.execute("");

        // Verify distribution was called
        assertEq(distributionModule.distributeCallCount(), 1);
        assertEq(cycleManager.currentCycleNumber(), 2);
    }

    function testResolveDistributionConditions() public {
        // Test: Not enough blocks passed
        (bool canExec,) = chainlinkAutomation.resolveDistribution();
        assertFalse(canExec);

        vm.roll(block.number + 101);

        // Test: No votes
        cycleManager.setCurrentVotes(0);
        (canExec,) = chainlinkAutomation.resolveDistribution();
        assertFalse(canExec);

        // Test: Insufficient yield
        cycleManager.setCurrentVotes(100);
        cycleManager.setAvailableYield(500);
        (canExec,) = chainlinkAutomation.resolveDistribution();
        assertFalse(canExec);

        // Test: System disabled
        cycleManager.setAvailableYield(2000);
        cycleManager.setEnabled(false);
        (canExec,) = chainlinkAutomation.resolveDistribution();
        assertFalse(canExec);

        // Test: All conditions met
        cycleManager.setEnabled(true);
        (canExec,) = chainlinkAutomation.resolveDistribution();
        assertTrue(canExec);
    }

    function testExecutionRevertsWhenNotResolved() public {
        // Try to execute when conditions not met
        vm.expectRevert(AutomationBase.NotResolved.selector);
        chainlinkAutomation.executeDistribution();
    }

    function testCycleManagerIntegration() public {
        // Check initial state
        assertEq(cycleManager.currentCycleNumber(), 1);
        assertEq(cycleManager.getCurrentVotes(), 100);
        assertEq(cycleManager.getAvailableYield(), 2000);

        // Advance and execute
        vm.roll(block.number + 101);
        chainlinkAutomation.executeDistribution();

        // Check state after execution
        assertEq(cycleManager.currentCycleNumber(), 2);
        assertEq(cycleManager.getCurrentVotes(), 0); // Reset after distribution
        assertEq(cycleManager.getAvailableYield(), 0); // Reset after distribution
        assertEq(cycleManager.getLastDistributionBlock(), block.number);
    }

    function testGetBlocksUntilNextCycle() public {
        // Initially should have 100 blocks until next cycle
        assertEq(cycleManager.getBlocksUntilNextCycle(), 100);

        // Advance 50 blocks
        vm.roll(block.number + 50);
        assertEq(cycleManager.getBlocksUntilNextCycle(), 50);

        // Advance past cycle length
        vm.roll(block.number + 60);
        assertEq(cycleManager.getBlocksUntilNextCycle(), 0);
    }

    function testCycleInfo() public {
        (uint256 cycleNum, uint256 startBlock, uint256 endBlock) = cycleManager.getCycleInfo();
        assertEq(cycleNum, 1);
        assertEq(startBlock, block.number);
        assertEq(endBlock, block.number + 100);

        // Execute distribution
        vm.roll(block.number + 101);
        chainlinkAutomation.executeDistribution();

        // Check updated cycle info
        (cycleNum, startBlock, endBlock) = cycleManager.getCycleInfo();
        assertEq(cycleNum, 2);
        assertEq(startBlock, block.number);
        assertEq(endBlock, block.number + 100);
    }

    function testBothAutomationTypesWork() public {
        // Test Chainlink automation
        vm.roll(block.number + 101);
        cycleManager.setCurrentVotes(100);
        cycleManager.setAvailableYield(2000);

        vm.prank(chainlinkKeeper);
        chainlinkAutomation.performUpkeep("");
        assertEq(distributionModule.distributeCallCount(), 1);

        // Test Gelato automation
        vm.roll(block.number + 101);
        cycleManager.setCurrentVotes(100);
        cycleManager.setAvailableYield(2000);

        vm.prank(gelatoExecutor);
        gelatoAutomation.execute("");
        assertEq(distributionModule.distributeCallCount(), 2);
    }

    function testMinYieldRequired() public {
        vm.roll(block.number + 101);

        // Set yield below minimum
        cycleManager.setAvailableYield(999);
        (bool canExec,) = chainlinkAutomation.resolveDistribution();
        assertFalse(canExec);

        // Set yield at minimum
        cycleManager.setAvailableYield(1000);
        (canExec,) = chainlinkAutomation.resolveDistribution();
        assertTrue(canExec);
    }
}
