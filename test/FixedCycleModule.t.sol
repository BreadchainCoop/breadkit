// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FixedCycleModule} from "../src/modules/FixedCycleModule.sol";
import {ICycleManager} from "../src/interfaces/ICycleManager.sol";
import {ICycleModule} from "../src/interfaces/ICycleModule.sol";

contract FixedCycleModuleTest is Test {
    FixedCycleModule internal module;

    function setUp() public {
        module = new FixedCycleModule();
        module.initialize(10, 0); // 10-block cycles starting now
    }

    function test_initialize_setsStateWithExplicitStart() public {
        FixedCycleModule m = new FixedCycleModule();
        uint256 startBlock = block.number + 5;
        m.initialize(7, startBlock);

        // Before start block, distribution is not ready
        assertFalse(m.isDistributionReady());

        vm.roll(startBlock);
        assertFalse(m.isDistributionReady());

        vm.roll(startBlock + 6);
        assertFalse(m.isDistributionReady());

        vm.roll(startBlock + 7);
        assertTrue(m.isDistributionReady());
    }

    function test_initialize_revertsOnZeroLength() public {
        FixedCycleModule m = new FixedCycleModule();
        vm.expectRevert(FixedCycleModule.InvalidCycleLength.selector);
        m.initialize(0, 0);
    }

    function test_isDistributionReady_falseBeforeEnd_trueAtOrAfterEnd() public {
        // length = 10 set in setUp, start = current block
        assertFalse(module.isDistributionReady());

        vm.roll(block.number + 9);
        assertFalse(module.isDistributionReady());

        vm.roll(block.number + 1); // reach 10 blocks elapsed
        assertTrue(module.isDistributionReady());

        vm.roll(block.number + 5);
        assertTrue(module.isDistributionReady());
    }

    function test_startNewCycle_requiresReady_andIncrements() public {
        vm.expectRevert(bytes("Cycle not complete"));
        module.startNewCycle();

        vm.roll(block.number + 10);

        vm.expectEmit(true, false, false, true, address(module));
        emit ICycleModule.NewCycleStarted(2, block.number);
        module.startNewCycle();

        assertEq(module.getCurrentCycle(), 2);

        ICycleManager.CycleInfo memory info = module.getCycleInfo();
        assertEq(info.cycleNumber, 2);
        assertEq(info.startBlock, block.number);
        assertEq(info.endBlock, block.number + 10);
        assertEq(info.blocksRemaining, 10);
        assertTrue(info.isActive);
    }

    function test_getBlocksUntilNextCycle_countsDown_toZero() public {
        uint256 remaining0 = module.getBlocksUntilNextCycle();
        assertEq(remaining0, 10);

        vm.roll(block.number + 4);
        assertEq(module.getBlocksUntilNextCycle(), 6);

        vm.roll(block.number + 6);
        assertEq(module.getBlocksUntilNextCycle(), 0);
    }

    function test_getCycleProgress_capsAt100_andTracks() public {
        assertEq(module.getCycleProgress(), 0);

        vm.roll(block.number + 5);
        assertEq(module.getCycleProgress(), 50);

        vm.roll(block.number + 10);
        assertEq(module.getCycleProgress(), 100);

        vm.roll(block.number + 20);
        assertEq(module.getCycleProgress(), 100);
    }

    function test_updateCycleLength_emits_and_applies() public {
        vm.expectRevert(FixedCycleModule.InvalidCycleLength.selector);
        module.updateCycleLength(0);

        vm.expectEmit(false, false, false, true, address(module));
        emit ICycleModule.CycleLengthUpdated(10, 15);
        module.updateCycleLength(15);

        ICycleManager.CycleInfo memory info = module.getCycleInfo();
        assertEq(info.endBlock, info.startBlock + 15);
        assertEq(module.getBlocksUntilNextCycle(), 15);
    }
}
