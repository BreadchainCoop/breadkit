// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CycleManager} from "../src/modules/CycleManager.sol";
import {FixedCycleModule} from "../src/modules/FixedCycleModule.sol";
import {ICycleManager} from "../src/interfaces/ICycleManager.sol";
import {ICycleModule} from "../src/interfaces/ICycleModule.sol";

contract CycleManagerTest is Test {
    CycleManager internal manager;
    FixedCycleModule internal module;

    address internal auth = address(0xA11CE);
    address internal notAuth = address(0xB0B);

    function setUp() public {
        manager = new CycleManager();
        module = new FixedCycleModule();
        module.initialize(10, 0);
        // grant authorization and set cycle module
        manager.setAuthorization(auth, true);
        vm.prank(auth);        
        manager.setCycleModule(address(module));
    }

    function test_isDistributionReady_combinesTimingVotesYield() public {
        // Before cycle end
        assertFalse(manager.isDistributionReady(1, 100, 10));

        // After cycle end but with zero votes
        vm.roll(block.number + 10);
        assertFalse(manager.isDistributionReady(0, 100, 10));

        // With votes but insufficient yield
        assertFalse(manager.isDistributionReady(5, 9, 10));

        // All conditions satisfied
        assertTrue(manager.isDistributionReady(5, 10, 10));
    }

    function test_validateCycleTransition_mirrorsModule() public {
        assertFalse(manager.validateCycleTransition());
        vm.roll(block.number + 10);
        assertTrue(manager.validateCycleTransition());
    }

    function test_startNewCycle_requiresAuth_andReadiness_andEmits_andStoresHistory() public {
        // Not authorized cannot start
        vm.prank(notAuth);
        vm.expectRevert(CycleManager.NotAuthorized.selector);
        manager.startNewCycle();

        // Authorized but not ready
        vm.prank(auth);
        vm.expectRevert(CycleManager.InvalidCycleTransition.selector);
        manager.startNewCycle();

        // Become ready
        vm.roll(block.number + 10);

        // Capture pre-transition info to compare history storage
        ICycleManager.CycleInfo memory beforeInfo = manager.getCycleInfo();

        vm.expectEmit(false, false, false, true, address(manager));
        emit ICycleManager.CycleStarted(beforeInfo.cycleNumber + 1, beforeInfo.endBlock, beforeInfo.endBlock + 10);
        vm.expectEmit(false, false, false, true, address(manager));
        emit ICycleManager.CycleTransitionValidated(beforeInfo.cycleNumber + 1);

        vm.prank(auth);
        manager.startNewCycle();

        // History stored for previous cycle
        // cycleHistory is public mapping; use generated getter
        (uint256 num, uint256 startB, uint256 endB, uint256 blocksRem, bool isActive) = manager.cycleHistory(beforeInfo
            .cycleNumber);
        assertEq(num, beforeInfo.cycleNumber);
        assertEq(startB, beforeInfo.startBlock);
        assertEq(endB, beforeInfo.endBlock);
        assertEq(blocksRem, 0);
        assertTrue(isActive);
    }

    function test_getCurrentCycle_and_getCycleInfo_proxyToModule() public {
        ICycleManager.CycleInfo memory infoBefore = manager.getCycleInfo();
        assertEq(infoBefore.cycleNumber, 1);

        vm.roll(block.number + 10);
        vm.prank(auth);
        manager.startNewCycle();

        assertEq(manager.getCurrentCycle(), 2);
        ICycleManager.CycleInfo memory info = manager.getCycleInfo();
        assertEq(info.cycleNumber, 2);
    }

    function test_setCycleModule_requiresAuth_andEmits() public {
        FixedCycleModule another = new FixedCycleModule();
        another.initialize(20, 0);

        vm.prank(notAuth);
        vm.expectRevert(CycleManager.NotAuthorized.selector);
        manager.setCycleModule(address(another));

        vm.prank(auth);
        vm.expectEmit(true, true, false, true, address(manager));
        emit ICycleManager.CycleModuleUpdated(address(module), address(another));
        manager.setCycleModule(address(another));

        // isDistributionReady reflects new module length
        vm.roll(block.number + 19);
        assertFalse(manager.isDistributionReady(1, 1, 1));
        vm.roll(block.number + 1);
        assertTrue(manager.isDistributionReady(1, 1, 1));
    }
}


