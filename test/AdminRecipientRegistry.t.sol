// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/Test.sol";
import {TestWrapper} from "./TestWrapper.sol";
import {AdminRecipientRegistry} from "../src/modules/AdminRecipientRegistry.sol";

contract AdminRecipientRegistryTest is TestWrapper {
    AdminRecipientRegistry public registry;
    
    address public constant ADMIN = address(0xAD);
    address public constant RECIPIENT_1 = address(0x1);
    address public constant RECIPIENT_2 = address(0x2);
    address public constant RECIPIENT_3 = address(0x3);
    address public constant RECIPIENT_4 = address(0x4);
    
    event RecipientAdded(address indexed recipient);
    event RecipientRemoved(address indexed recipient);

    function setUp() public {
        registry = new AdminRecipientRegistry();
        registry.initialize(ADMIN);
    }

    function test_Initialize() public view {
        assertEq(registry.owner(), ADMIN);
        assertEq(registry.getRecipientCount(), 0);
    }

    function test_AddRecipient() public {
        vm.prank(ADMIN);
        vm.expectEmit(true, false, false, false);
        emit RecipientAdded(RECIPIENT_1);
        registry.addRecipient(RECIPIENT_1);
        
        assertTrue(registry.isRecipient(RECIPIENT_1));
        assertEq(registry.getRecipientCount(), 1);
        
        address[] memory recipients = registry.getRecipients();
        assertEq(recipients.length, 1);
        assertEq(recipients[0], RECIPIENT_1);
    }

    function test_AddMultipleRecipients() public {
        address[] memory toAdd = new address[](3);
        toAdd[0] = RECIPIENT_1;
        toAdd[1] = RECIPIENT_2;
        toAdd[2] = RECIPIENT_3;
        
        vm.prank(ADMIN);
        registry.addRecipients(toAdd);
        
        assertEq(registry.getRecipientCount(), 3);
        assertTrue(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        assertTrue(registry.isRecipient(RECIPIENT_3));
    }

    function test_RemoveRecipient() public {
        vm.startPrank(ADMIN);
        registry.addRecipient(RECIPIENT_1);
        registry.addRecipient(RECIPIENT_2);
        
        vm.expectEmit(true, false, false, false);
        emit RecipientRemoved(RECIPIENT_1);
        registry.removeRecipient(RECIPIENT_1);
        vm.stopPrank();
        
        assertFalse(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        assertEq(registry.getRecipientCount(), 1);
    }

    function test_RemoveMultipleRecipients() public {
        vm.startPrank(ADMIN);
        
        // Add recipients
        address[] memory toAdd = new address[](4);
        toAdd[0] = RECIPIENT_1;
        toAdd[1] = RECIPIENT_2;
        toAdd[2] = RECIPIENT_3;
        toAdd[3] = RECIPIENT_4;
        registry.addRecipients(toAdd);
        
        // Remove some
        address[] memory toRemove = new address[](2);
        toRemove[0] = RECIPIENT_1;
        toRemove[1] = RECIPIENT_3;
        registry.removeRecipients(toRemove);
        
        vm.stopPrank();
        
        assertFalse(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        assertFalse(registry.isRecipient(RECIPIENT_3));
        assertTrue(registry.isRecipient(RECIPIENT_4));
        assertEq(registry.getRecipientCount(), 2);
    }

    function test_RevertOnInvalidRecipient() public {
        vm.prank(ADMIN);
        vm.expectRevert(AdminRecipientRegistry.InvalidRecipient.selector);
        registry.addRecipient(address(0));
    }

    function test_RevertOnDuplicateRecipient() public {
        vm.startPrank(ADMIN);
        registry.addRecipient(RECIPIENT_1);
        
        vm.expectRevert(AdminRecipientRegistry.RecipientAlreadyExists.selector);
        registry.addRecipient(RECIPIENT_1);
        vm.stopPrank();
    }

    function test_RevertOnRemovingNonExistent() public {
        vm.prank(ADMIN);
        vm.expectRevert(AdminRecipientRegistry.RecipientNotFound.selector);
        registry.removeRecipient(RECIPIENT_1);
    }

    function test_OnlyAdminCanAdd() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.addRecipient(RECIPIENT_1);
    }

    function test_OnlyAdminCanRemove() public {
        vm.prank(ADMIN);
        registry.addRecipient(RECIPIENT_1);
        
        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.removeRecipient(RECIPIENT_1);
    }

    function test_TransferAdmin() public {
        address newAdmin = address(0xBEEF);
        
        vm.prank(ADMIN);
        registry.transferAdmin(newAdmin);
        
        assertEq(registry.owner(), newAdmin);
        
        // New admin can add
        vm.prank(newAdmin);
        registry.addRecipient(RECIPIENT_1);
        assertTrue(registry.isRecipient(RECIPIENT_1));
        
        // Old admin cannot
        vm.prank(ADMIN);
        vm.expectRevert();
        registry.addRecipient(RECIPIENT_2);
    }

    function test_LargeScaleOperations() public {
        vm.startPrank(ADMIN);
        
        // Add many recipients
        uint256 count = 100;
        for (uint256 i = 1; i <= count; i++) {
            registry.addRecipient(address(uint160(i)));
        }
        
        assertEq(registry.getRecipientCount(), count);
        
        // Remove half
        for (uint256 i = 1; i <= 50; i++) {
            registry.removeRecipient(address(uint160(i)));
        }
        
        assertEq(registry.getRecipientCount(), 50);
        
        vm.stopPrank();
    }
}