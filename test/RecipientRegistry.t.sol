// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/Test.sol";
import {TestWrapper} from "./TestWrapper.sol";
import {RecipientRegistry} from "../src/modules/RecipientRegistry.sol";
import {IRecipientRegistry} from "../src/interfaces/IRecipientRegistry.sol";

contract RecipientRegistryTest is TestWrapper {
    RecipientRegistry public registry;
    
    address public constant RECIPIENT_1 = address(0x1);
    address public constant RECIPIENT_2 = address(0x2);
    address public constant RECIPIENT_3 = address(0x3);
    address public constant RECIPIENT_4 = address(0x4);
    
    event RecipientQueued(address indexed recipient, bool isAddition);
    event RecipientAdded(address indexed recipient);
    event RecipientRemoved(address indexed recipient);
    event QueueProcessed(uint256 added, uint256 removed);

    function setUp() public {
        registry = new RecipientRegistry();
        registry.initialize(address(this));
    }

    function test_Initialize() public view {
        assertEq(registry.owner(), address(this));
        assertEq(registry.getRecipientCount(), 0);
    }

    function test_QueueRecipientAddition() public {
        vm.expectEmit(true, true, false, true);
        emit RecipientQueued(RECIPIENT_1, true);
        
        registry.queueRecipientAddition(RECIPIENT_1);
        
        address[] memory queued = registry.getQueuedAdditions();
        assertEq(queued.length, 1);
        assertEq(queued[0], RECIPIENT_1);
        assertTrue(registry.isQueuedForAddition(RECIPIENT_1));
    }

    function test_QueueMultipleAdditions() public {
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);
        registry.queueRecipientAddition(RECIPIENT_3);
        
        address[] memory queued = registry.getQueuedAdditions();
        assertEq(queued.length, 3);
        assertEq(queued[0], RECIPIENT_1);
        assertEq(queued[1], RECIPIENT_2);
        assertEq(queued[2], RECIPIENT_3);
    }

    function test_ProcessQueueAdditions() public {
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);
        
        vm.expectEmit(true, false, false, true);
        emit RecipientAdded(RECIPIENT_1);
        vm.expectEmit(true, false, false, true);
        emit RecipientAdded(RECIPIENT_2);
        vm.expectEmit(false, false, false, true);
        emit QueueProcessed(2, 0);
        
        registry.processQueue();
        
        assertEq(registry.getRecipientCount(), 2);
        assertTrue(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        
        // Queue should be cleared
        assertEq(registry.getQueuedAdditions().length, 0);
    }

    function test_QueueRecipientRemoval() public {
        // First add a recipient
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.processQueue();
        
        // Queue removal
        vm.expectEmit(true, true, false, true);
        emit RecipientQueued(RECIPIENT_1, false);
        
        registry.queueRecipientRemoval(RECIPIENT_1);
        
        address[] memory queued = registry.getQueuedRemovals();
        assertEq(queued.length, 1);
        assertEq(queued[0], RECIPIENT_1);
        assertTrue(registry.isQueuedForRemoval(RECIPIENT_1));
    }

    function test_ProcessQueueRemovals() public {
        // Add recipients
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);
        registry.queueRecipientAddition(RECIPIENT_3);
        registry.processQueue();
        
        // Queue removals
        registry.queueRecipientRemoval(RECIPIENT_1);
        registry.queueRecipientRemoval(RECIPIENT_3);
        
        vm.expectEmit(true, false, false, true);
        emit RecipientRemoved(RECIPIENT_1);
        vm.expectEmit(true, false, false, true);
        emit RecipientRemoved(RECIPIENT_3);
        vm.expectEmit(false, false, false, true);
        emit QueueProcessed(0, 2);
        
        registry.processQueue();
        
        // Only RECIPIENT_2 should remain
        assertEq(registry.getRecipientCount(), 1);
        assertFalse(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        assertFalse(registry.isRecipient(RECIPIENT_3));
        
        // Queues should be cleared
        assertEq(registry.getQueuedRemovals().length, 0);
    }

    function test_ProcessQueueMixed() public {
        // Add initial recipients
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);
        registry.processQueue();
        
        // Queue mixed operations
        registry.queueRecipientAddition(RECIPIENT_3);
        registry.queueRecipientAddition(RECIPIENT_4);
        registry.queueRecipientRemoval(RECIPIENT_1);
        
        vm.expectEmit(false, false, false, true);
        emit QueueProcessed(2, 1);
        
        registry.processQueue();
        
        // Should have RECIPIENT_2, RECIPIENT_3, RECIPIENT_4
        assertEq(registry.getRecipientCount(), 3);
        assertFalse(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        assertTrue(registry.isRecipient(RECIPIENT_3));
        assertTrue(registry.isRecipient(RECIPIENT_4));
    }

    function test_ClearAdditionQueue() public {
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);
        
        assertEq(registry.getQueuedAdditions().length, 2);
        
        registry.clearAdditionQueue();
        
        assertEq(registry.getQueuedAdditions().length, 0);
    }

    function test_ClearRemovalQueue() public {
        // Add recipients first
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);
        registry.processQueue();
        
        // Queue removals
        registry.queueRecipientRemoval(RECIPIENT_1);
        registry.queueRecipientRemoval(RECIPIENT_2);
        
        assertEq(registry.getQueuedRemovals().length, 2);
        
        registry.clearRemovalQueue();
        
        assertEq(registry.getQueuedRemovals().length, 0);
    }

    function test_GetRecipients() public {
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);
        registry.queueRecipientAddition(RECIPIENT_3);
        registry.processQueue();
        
        address[] memory recipients = registry.getRecipients();
        assertEq(recipients.length, 3);
        assertEq(recipients[0], RECIPIENT_1);
        assertEq(recipients[1], RECIPIENT_2);
        assertEq(recipients[2], RECIPIENT_3);
    }

    function test_RevertOnInvalidRecipient() public {
        vm.expectRevert(IRecipientRegistry.InvalidRecipient.selector);
        registry.queueRecipientAddition(address(0));
    }

    function test_RevertOnDuplicateRecipient() public {
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.processQueue();
        
        vm.expectRevert(IRecipientRegistry.RecipientAlreadyExists.selector);
        registry.queueRecipientAddition(RECIPIENT_1);
    }

    function test_RevertOnDuplicateQueuedAddition() public {
        registry.queueRecipientAddition(RECIPIENT_1);
        
        vm.expectRevert(IRecipientRegistry.RecipientAlreadyQueued.selector);
        registry.queueRecipientAddition(RECIPIENT_1);
    }

    function test_RevertOnRemovalOfNonExistent() public {
        vm.expectRevert(IRecipientRegistry.RecipientNotFound.selector);
        registry.queueRecipientRemoval(RECIPIENT_1);
    }

    function test_RevertOnDuplicateQueuedRemoval() public {
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.processQueue();
        
        registry.queueRecipientRemoval(RECIPIENT_1);
        
        vm.expectRevert(IRecipientRegistry.RecipientAlreadyQueued.selector);
        registry.queueRecipientRemoval(RECIPIENT_1);
    }

    function test_OnlyOwnerCanQueue() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.queueRecipientAddition(RECIPIENT_1);
        
        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.queueRecipientRemoval(RECIPIENT_1);
    }

    function test_OnlyOwnerCanClearQueues() public {
        registry.queueRecipientAddition(RECIPIENT_1);
        
        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.clearAdditionQueue();
        
        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.clearRemovalQueue();
    }

    function test_AnyoneCanProcessQueue() public {
        registry.queueRecipientAddition(RECIPIENT_1);
        
        vm.prank(address(0xdead));
        registry.processQueue();
        
        assertTrue(registry.isRecipient(RECIPIENT_1));
    }

    function test_EmptyQueueProcess() public {
        // Should not revert on empty queue
        registry.processQueue();
        assertEq(registry.getRecipientCount(), 0);
    }

    function test_LargeScaleOperations() public {
        // Add many recipients
        uint256 count = 100;
        for (uint256 i = 1; i <= count; i++) {
            registry.queueRecipientAddition(address(uint160(i)));
        }
        
        registry.processQueue();
        assertEq(registry.getRecipientCount(), count);
        
        // Remove half
        for (uint256 i = 1; i <= 50; i++) {
            registry.queueRecipientRemoval(address(uint160(i)));
        }
        
        registry.processQueue();
        assertEq(registry.getRecipientCount(), 50);
    }
}