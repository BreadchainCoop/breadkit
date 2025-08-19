// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./mocks/MockDistributionManagerSimple.sol";

contract MockDistributionManagerTest is Test {
    MockDistributionManagerSimple public manager;

    event MockDistributionExecuted(uint256 blockNumber);

    function setUp() public {
        manager = new MockDistributionManagerSimple();
    }

    function test_InitialState() public view {
        assertEq(manager.BLOCKS_PER_CYCLE(), 200, "Blocks per cycle should be 200");
        assertEq(manager.getLastDistributionBlock(), block.number, "Last distribution should be deployment block");
        assertFalse(manager.isDistributionReady(), "Should not be ready immediately after deployment");
    }

    function test_IsDistributionReady_After200Blocks() public {
        // Fast forward 199 blocks
        vm.roll(block.number + 199);
        assertFalse(manager.isDistributionReady(), "Should not be ready at 199 blocks");

        // Fast forward to exactly 200 blocks
        vm.roll(block.number + 1);
        assertTrue(manager.isDistributionReady(), "Should be ready at 200 blocks");

        // Fast forward more
        vm.roll(block.number + 100);
        assertTrue(manager.isDistributionReady(), "Should still be ready after 200 blocks");
    }

    function test_BlocksUntilDistribution() public {
        assertEq(manager.blocksUntilDistribution(), 200, "Should be 200 blocks until distribution");

        vm.roll(block.number + 100);
        assertEq(manager.blocksUntilDistribution(), 100, "Should be 100 blocks until distribution");

        vm.roll(block.number + 100);
        assertEq(manager.blocksUntilDistribution(), 0, "Should be 0 blocks until distribution");

        vm.roll(block.number + 50);
        assertEq(manager.blocksUntilDistribution(), 0, "Should still be 0 when overdue");
    }

    function test_ExecuteDistribution() public {
        // Try to execute too early
        vm.expectRevert("Not ready");
        manager.executeDistribution();

        // Fast forward 200 blocks
        vm.roll(block.number + 200);

        // Execute distribution
        vm.expectEmit(true, true, true, true);
        emit MockDistributionExecuted(block.number);
        manager.executeDistribution();

        // Check state after execution
        assertEq(manager.getLastDistributionBlock(), block.number, "Last distribution should be updated");
        assertFalse(manager.isDistributionReady(), "Should not be ready immediately after execution");

        // Check blocks until next distribution
        assertEq(manager.blocksUntilDistribution(), 200, "Should be 200 blocks until next distribution");
    }

    function test_MultipleDistributions() public {
        uint256 startBlock = block.number;

        // First distribution
        vm.roll(startBlock + 200);
        assertTrue(manager.isDistributionReady());
        manager.executeDistribution();

        // Second distribution
        vm.roll(block.number + 200);
        assertTrue(manager.isDistributionReady());
        manager.executeDistribution();

        // Third distribution
        vm.roll(block.number + 200);
        assertTrue(manager.isDistributionReady());
        manager.executeDistribution();

        // Should have executed 3 distributions
        assertEq(manager.getLastDistributionBlock(), startBlock + 600);
    }
}
