// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/Test.sol";
import {TestWrapper} from "./TestWrapper.sol";
import {RecipientRegistry} from "../src/modules/RecipientRegistry.sol";
import {IRecipientRegistry} from "../src/interfaces/IRecipientRegistry.sol";
import {QueueManager} from "../src/modules/QueueManager.sol";

contract RecipientRegistryTest is TestWrapper {
    RecipientRegistry public registry;

    address public constant RECIPIENT_1 = address(0x1);
    address public constant RECIPIENT_2 = address(0x2);
    address public constant RECIPIENT_3 = address(0x3);

    uint256 public constant DEFAULT_DELAY = 2 days;
    uint256 public constant PERCENTAGE_25 = 2500; // 25%
    uint256 public constant PERCENTAGE_50 = 5000; // 50%
    uint256 public constant PERCENTAGE_75 = 7500; // 75%
    uint256 public constant PERCENTAGE_100 = 10000; // 100%

    event RecipientQueued(uint256 indexed changeId, uint256 changeType, address recipient, uint256 executeAfter);
    event RecipientAdded(address indexed recipient, uint256 percentage, string metadata);
    event RecipientRemoved(address indexed recipient);
    event RecipientUpdated(address indexed recipient, uint256 percentage, string metadata);
    event ChangeExecuted(uint256 indexed changeId);
    event ChangeCancelled(uint256 indexed changeId);
    event DelayUpdated(uint256 oldDelay, uint256 newDelay);

    function setUp() public {
        registry = new RecipientRegistry();
        registry.initialize(address(this), DEFAULT_DELAY);
    }

    function test_Initialize() public view {
        assertEq(registry.owner(), address(this));
        assertEq(registry.getDelay(), DEFAULT_DELAY);
        assertEq(registry.getActiveRecipientCount(), 0);
    }

    function test_QueueAddRecipient() public {
        uint256 changeId = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");

        IRecipientRegistry.QueuedChange memory change = registry.getQueuedChange(changeId);
        assertEq(change.changeType, 0); // add
        assertEq(change.recipient, RECIPIENT_1);
        assertEq(change.percentage, PERCENTAGE_25);
        assertEq(change.metadata, "Recipient 1");
        assertFalse(change.executed);
        assertFalse(change.cancelled);
    }

    function test_ExecuteAddRecipient() public {
        uint256 changeId = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");

        // Fast forward time
        vm.warp(block.timestamp + DEFAULT_DELAY + 1);

        registry.executeChange(changeId);

        assertTrue(registry.isActiveRecipient(RECIPIENT_1));
        assertEq(registry.getActiveRecipientCount(), 1);

        IRecipientRegistry.Recipient memory recipient = registry.getRecipient(RECIPIENT_1);
        assertEq(recipient.addr, RECIPIENT_1);
        assertEq(recipient.percentage, PERCENTAGE_25);
        assertEq(recipient.metadata, "Recipient 1");
        assertTrue(recipient.isActive);
    }

    function test_QueueRemoveRecipient() public {
        // First add a recipient
        uint256 addId = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");
        vm.warp(block.timestamp + DEFAULT_DELAY + 1);
        registry.executeChange(addId);

        // Queue removal
        uint256 removeId = registry.queueRemoveRecipient(RECIPIENT_1);

        IRecipientRegistry.QueuedChange memory change = registry.getQueuedChange(removeId);
        assertEq(change.changeType, 1); // remove
        assertEq(change.recipient, RECIPIENT_1);
    }

    function test_ExecuteRemoveRecipient() public {
        // First add a recipient
        uint256 addId = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");
        vm.warp(block.timestamp + DEFAULT_DELAY + 1);
        registry.executeChange(addId);

        // Queue and execute removal
        uint256 removeId = registry.queueRemoveRecipient(RECIPIENT_1);
        vm.warp(block.timestamp + DEFAULT_DELAY + 1);
        registry.executeChange(removeId);

        assertFalse(registry.isActiveRecipient(RECIPIENT_1));
        assertEq(registry.getActiveRecipientCount(), 0);
    }

    function test_QueueUpdateRecipient() public {
        // First add a recipient
        uint256 addId = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");
        vm.warp(block.timestamp + DEFAULT_DELAY + 1);
        registry.executeChange(addId);

        // Queue update
        uint256 updateId = registry.queueUpdateRecipient(RECIPIENT_1, PERCENTAGE_50, "Updated Recipient 1");

        IRecipientRegistry.QueuedChange memory change = registry.getQueuedChange(updateId);
        assertEq(change.changeType, 2); // update
        assertEq(change.recipient, RECIPIENT_1);
        assertEq(change.percentage, PERCENTAGE_50);
        assertEq(change.metadata, "Updated Recipient 1");
    }

    function test_ExecuteUpdateRecipient() public {
        // First add a recipient
        uint256 addId = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");
        vm.warp(block.timestamp + DEFAULT_DELAY + 1);
        registry.executeChange(addId);

        // Queue and execute update
        uint256 updateId = registry.queueUpdateRecipient(RECIPIENT_1, PERCENTAGE_50, "Updated Recipient 1");
        vm.warp(block.timestamp + DEFAULT_DELAY + 1);
        registry.executeChange(updateId);

        IRecipientRegistry.Recipient memory recipient = registry.getRecipient(RECIPIENT_1);
        assertEq(recipient.percentage, PERCENTAGE_50);
        assertEq(recipient.metadata, "Updated Recipient 1");
    }

    function test_CancelChange() public {
        uint256 changeId = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");

        registry.cancelChange(changeId);

        IRecipientRegistry.QueuedChange memory change = registry.getQueuedChange(changeId);
        assertTrue(change.cancelled);

        // Should not be able to execute cancelled change
        vm.warp(block.timestamp + DEFAULT_DELAY + 1);
        vm.expectRevert(QueueManager.ChangeIsCancelled.selector);
        registry.executeChange(changeId);
    }

    function test_PercentageValidation() public {
        // Add recipients with total 100%
        uint256 id1 = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_50, "Recipient 1");
        uint256 id2 = registry.queueAddRecipient(RECIPIENT_2, PERCENTAGE_50, "Recipient 2");

        vm.warp(block.timestamp + DEFAULT_DELAY + 1);
        registry.executeChange(id1);
        registry.executeChange(id2);

        assertTrue(registry.validatePercentages());
        assertEq(registry.getTotalAllocatedPercentage(), PERCENTAGE_100);

        // Try to add recipient that would exceed 100%
        uint256 id3 = registry.queueAddRecipient(RECIPIENT_3, PERCENTAGE_25, "Recipient 3");
        vm.warp(block.timestamp + DEFAULT_DELAY + 1);

        vm.expectRevert(IRecipientRegistry.TotalPercentageExceeds100.selector);
        registry.executeChange(id3);
    }

    function test_MultipleRecipients() public {
        // Add multiple recipients
        uint256 id1 = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");
        uint256 id2 = registry.queueAddRecipient(RECIPIENT_2, PERCENTAGE_25, "Recipient 2");
        uint256 id3 = registry.queueAddRecipient(RECIPIENT_3, PERCENTAGE_50, "Recipient 3");

        vm.warp(block.timestamp + DEFAULT_DELAY + 1);
        registry.executeChange(id1);
        registry.executeChange(id2);
        registry.executeChange(id3);

        assertEq(registry.getActiveRecipientCount(), 3);
        assertEq(registry.getTotalAllocatedPercentage(), PERCENTAGE_100);

        IRecipientRegistry.Recipient[] memory recipients = registry.getActiveRecipients();
        assertEq(recipients.length, 3);
    }

    function test_UpdateDelay() public {
        uint256 newDelay = 5 days;

        vm.expectEmit(true, true, true, true);
        emit DelayUpdated(DEFAULT_DELAY, newDelay);

        registry.setDelay(newDelay);
        assertEq(registry.getDelay(), newDelay);

        // New changes should use new delay
        uint256 changeId = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");
        IRecipientRegistry.QueuedChange memory change = registry.getQueuedChange(changeId);
        assertEq(change.executeAfter, block.timestamp + newDelay);
    }

    function test_GetPendingChanges() public {
        uint256 id1 = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");
        uint256 id2 = registry.queueAddRecipient(RECIPIENT_2, PERCENTAGE_25, "Recipient 2");

        uint256[] memory pending = registry.getPendingChanges();
        assertEq(pending.length, 2);
        assertEq(pending[0], id1);
        assertEq(pending[1], id2);

        // Execute one change
        vm.warp(block.timestamp + DEFAULT_DELAY + 1);
        registry.executeChange(id1);

        pending = registry.getPendingChanges();
        assertEq(pending.length, 1);
        assertEq(pending[0], id2);
    }

    function test_RevertOnInvalidRecipient() public {
        vm.expectRevert(IRecipientRegistry.InvalidRecipient.selector);
        registry.queueAddRecipient(address(0), PERCENTAGE_25, "Invalid");
    }

    function test_RevertOnInvalidPercentage() public {
        vm.expectRevert(IRecipientRegistry.InvalidPercentage.selector);
        registry.queueAddRecipient(RECIPIENT_1, 0, "Zero percentage");

        vm.expectRevert(IRecipientRegistry.InvalidPercentage.selector);
        registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_100 + 1, "Over 100%");
    }

    function test_RevertOnDuplicateRecipient() public {
        uint256 id1 = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");
        vm.warp(block.timestamp + DEFAULT_DELAY + 1);
        registry.executeChange(id1);

        vm.expectRevert(IRecipientRegistry.RecipientAlreadyExists.selector);
        registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Duplicate");
    }

    function test_RevertOnEarlyExecution() public {
        uint256 changeId = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");

        vm.expectRevert();
        registry.executeChange(changeId);
    }

    function test_RevertOnNonExistentRecipient() public {
        vm.expectRevert(IRecipientRegistry.RecipientNotFound.selector);
        registry.queueRemoveRecipient(RECIPIENT_1);

        vm.expectRevert(IRecipientRegistry.RecipientNotFound.selector);
        registry.queueUpdateRecipient(RECIPIENT_1, PERCENTAGE_25, "Non-existent");
    }

    function test_OnlyOwnerCanQueue() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Unauthorized");
    }

    function test_OnlyOwnerCanCancel() public {
        uint256 changeId = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");

        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.cancelChange(changeId);
    }

    function test_AnyoneCanExecute() public {
        uint256 changeId = registry.queueAddRecipient(RECIPIENT_1, PERCENTAGE_25, "Recipient 1");
        vm.warp(block.timestamp + DEFAULT_DELAY + 1);

        vm.prank(address(0xdead));
        registry.executeChange(changeId);

        assertTrue(registry.isActiveRecipient(RECIPIENT_1));
    }
}
