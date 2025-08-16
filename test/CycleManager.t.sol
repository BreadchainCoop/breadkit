// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/CycleManager.sol";
import "../src/abstracts/AbstractCycleManager.sol";

contract CycleManagerTest is Test {
    CycleManager public cycleManager;
    address public owner = address(this);
    address public user = address(0x1);

    uint256 constant CYCLE_LENGTH = 100; // 100 blocks per cycle
    uint256 constant START_BLOCK = 1000;

    function setUp() public {
        vm.roll(START_BLOCK);
        cycleManager = new CycleManager(CYCLE_LENGTH, START_BLOCK);
    }

    function testInitialState() public view {
        assertEq(cycleManager.getCurrentCycle(), 1);
        assertEq(cycleManager.cycleLength(), CYCLE_LENGTH);
        assertEq(cycleManager.lastCycleStartBlock(), START_BLOCK);
        assertTrue(cycleManager.authorized(owner));
    }

    function testCycleCompletion() public {
        assertFalse(cycleManager.isCycleComplete());

        // Move to end of cycle
        vm.roll(START_BLOCK + CYCLE_LENGTH);
        assertTrue(cycleManager.isCycleComplete());
    }

    function testStartNewCycle() public {
        // Move to end of cycle
        vm.roll(START_BLOCK + CYCLE_LENGTH);

        uint256 currentBlock = block.number;
        cycleManager.startNewCycle();

        assertEq(cycleManager.getCurrentCycle(), 2);
        assertEq(cycleManager.lastCycleStartBlock(), currentBlock);
        assertFalse(cycleManager.isCycleComplete());
    }

    function testCannotStartNewCycleEarly() public {
        // Try to start new cycle before current one is complete
        vm.roll(START_BLOCK + CYCLE_LENGTH - 1);

        vm.expectRevert(AbstractCycleManager.InvalidCycleTransition.selector);
        cycleManager.startNewCycle();
    }

    function testUnauthorizedCannotStartCycle() public {
        vm.roll(START_BLOCK + CYCLE_LENGTH);

        vm.prank(user);
        vm.expectRevert(AbstractCycleManager.NotAuthorized.selector);
        cycleManager.startNewCycle();
    }

    function testAuthorization() public {
        assertFalse(cycleManager.authorized(user));

        cycleManager.setAuthorization(user, true);
        assertTrue(cycleManager.authorized(user));

        cycleManager.setAuthorization(user, false);
        assertFalse(cycleManager.authorized(user));
    }

    function testGetCycleInfo() public {
        CycleManager.CycleInfo memory info = cycleManager.getCycleInfo();

        assertEq(info.cycleNumber, 1);
        assertEq(info.startBlock, START_BLOCK);
        assertEq(info.endBlock, START_BLOCK + CYCLE_LENGTH);
        assertEq(info.blocksRemaining, CYCLE_LENGTH);
        assertTrue(info.isActive);

        // Move halfway through cycle
        vm.roll(START_BLOCK + 50);
        info = cycleManager.getCycleInfo();
        assertEq(info.blocksRemaining, 50);
    }

    function testGetBlocksUntilNextCycle() public view {
        assertEq(cycleManager.getBlocksUntilNextCycle(), CYCLE_LENGTH);
    }

    function testGetBlocksUntilNextCyclePartway() public {
        vm.roll(START_BLOCK + 25);
        assertEq(cycleManager.getBlocksUntilNextCycle(), 75);
    }

    function testGetBlocksUntilNextCycleComplete() public {
        vm.roll(START_BLOCK + CYCLE_LENGTH);
        assertEq(cycleManager.getBlocksUntilNextCycle(), 0);
    }

    function testGetCycleProgress() public view {
        assertEq(cycleManager.getCycleProgress(), 0);
    }

    function testGetCycleProgressPartway() public {
        vm.roll(START_BLOCK + 50);
        assertEq(cycleManager.getCycleProgress(), 50);
    }

    function testGetCycleProgressComplete() public {
        vm.roll(START_BLOCK + CYCLE_LENGTH);
        assertEq(cycleManager.getCycleProgress(), 100);
    }

    function testUpdateCycleLength() public {
        uint256 newLength = 200;
        cycleManager.updateCycleLength(newLength);
        assertEq(cycleManager.cycleLength(), newLength);
    }

    function testCannotUpdateCycleLengthToZero() public {
        vm.expectRevert(AbstractCycleManager.InvalidCycleLength.selector);
        cycleManager.updateCycleLength(0);
    }

    function testUnauthorizedCannotUpdateCycleLength() public {
        vm.prank(user);
        vm.expectRevert(AbstractCycleManager.NotAuthorized.selector);
        cycleManager.updateCycleLength(200);
    }

    function testMultipleCycles() public {
        // Complete first cycle
        vm.roll(START_BLOCK + CYCLE_LENGTH);
        cycleManager.startNewCycle();
        assertEq(cycleManager.getCurrentCycle(), 2);

        // Complete second cycle
        vm.roll(START_BLOCK + CYCLE_LENGTH + CYCLE_LENGTH);
        cycleManager.startNewCycle();
        assertEq(cycleManager.getCurrentCycle(), 3);

        // Verify cycle info
        CycleManager.CycleInfo memory info = cycleManager.getCycleInfo();
        assertEq(info.cycleNumber, 3);
        assertEq(info.startBlock, START_BLOCK + CYCLE_LENGTH + CYCLE_LENGTH);
    }
}
