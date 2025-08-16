// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BreadKitDistribution} from "../src/modules/BreadKitDistribution.sol";
import {YieldCollector} from "../src/modules/YieldCollector.sol";
import {IDistributionModule} from "../src/interfaces/IDistributionModule.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockVotingModule} from "./mocks/MockVotingModule.sol";
import {MockRecipientRegistry} from "./mocks/MockRecipientRegistry.sol";
import {MockFixedSplitModule} from "./mocks/MockFixedSplitModule.sol";
import {MockYieldModule} from "./mocks/MockYieldModule.sol";

contract DistributionModuleTest is Test {
    BreadKitDistribution public distribution;
    YieldCollector public yieldCollector;
    MockERC20 public yieldToken;
    MockVotingModule public votingModule;
    MockRecipientRegistry public recipientRegistry;
    MockFixedSplitModule public fixedSplitModule;
    
    address public owner = address(this);
    address public emergencyAdmin = address(0x911);
    address public recipient1 = address(0x1);
    address public recipient2 = address(0x2);
    address public recipient3 = address(0x3);
    
    uint256 public constant CYCLE_LENGTH = 100;
    uint256 public constant YIELD_FIXED_SPLIT_DIVISOR = 4;
    
    event YieldDistributed(
        uint256 totalYield,
        uint256 totalVotes,
        address[] recipients,
        uint256[] votedDistributions,
        uint256[] fixedDistributions
    );
    
    function setUp() public {
        yieldToken = new MockERC20("Yield Token", "YIELD");
        distribution = new BreadKitDistribution();
        distribution.initialize(address(yieldToken), CYCLE_LENGTH, YIELD_FIXED_SPLIT_DIVISOR);
        
        yieldCollector = new YieldCollector(address(yieldToken));
        votingModule = new MockVotingModule();
        recipientRegistry = new MockRecipientRegistry();
        fixedSplitModule = new MockFixedSplitModule();
        
        distribution.setYieldCollector(address(yieldCollector));
        distribution.setVotingModule(address(votingModule));
        distribution.setRecipientRegistry(address(recipientRegistry));
        distribution.setFixedSplitModule(address(fixedSplitModule));
        distribution.setEmergencyAdmin(emergencyAdmin);
        
        yieldCollector.setDistributionManager(address(distribution));
        
        recipientRegistry.addRecipient(recipient1);
        recipientRegistry.addRecipient(recipient2);
        recipientRegistry.addRecipient(recipient3);
        
        votingModule.setVotes([uint256(300), uint256(500), uint256(200)]);
    }
    
    function testInitialization() public view {
        assertEq(distribution.cycleLength(), CYCLE_LENGTH);
        assertEq(distribution.yieldFixedSplitDivisor(), YIELD_FIXED_SPLIT_DIVISOR);
        assertEq(distribution.yieldToken(), address(yieldToken));
        assertEq(distribution.emergencyAdmin(), emergencyAdmin);
    }
    
    function testDistributeYield() public {
        yieldToken.mint(address(distribution), 1000 ether);
        
        vm.roll(block.number + CYCLE_LENGTH + 1);
        
        uint256 recipient1BalanceBefore = yieldToken.balanceOf(recipient1);
        uint256 recipient2BalanceBefore = yieldToken.balanceOf(recipient2);
        uint256 recipient3BalanceBefore = yieldToken.balanceOf(recipient3);
        
        distribution.distributeYield();
        
        uint256 recipient1BalanceAfter = yieldToken.balanceOf(recipient1);
        uint256 recipient2BalanceAfter = yieldToken.balanceOf(recipient2);
        uint256 recipient3BalanceAfter = yieldToken.balanceOf(recipient3);
        
        assertGt(recipient1BalanceAfter, recipient1BalanceBefore);
        assertGt(recipient2BalanceAfter, recipient2BalanceBefore);
        assertGt(recipient3BalanceAfter, recipient3BalanceBefore);
        
        uint256 totalDistributed = (recipient1BalanceAfter - recipient1BalanceBefore) +
                                   (recipient2BalanceAfter - recipient2BalanceBefore) +
                                   (recipient3BalanceAfter - recipient3BalanceBefore);
        
        assertEq(totalDistributed, 1000 ether);
    }
    
    function testDistributionWithFixedAndVotedSplit() public {
        uint256 totalYield = 1000 ether;
        yieldToken.mint(address(distribution), totalYield);
        
        vm.roll(block.number + CYCLE_LENGTH + 1);
        
        distribution.distributeYield();
        
        uint256 expectedFixedAmount = totalYield / YIELD_FIXED_SPLIT_DIVISOR;
        uint256 expectedVotedAmount = totalYield - expectedFixedAmount;
        
        uint256 expectedFixedPerRecipient = expectedFixedAmount / 3;
        
        uint256 recipient2VotedAmount = (expectedVotedAmount * 500) / 1000;
        uint256 recipient2Total = expectedFixedPerRecipient + recipient2VotedAmount;
        
        assertApproxEqAbs(yieldToken.balanceOf(recipient2), recipient2Total, 3);
    }
    
    function testCannotDistributeBeforeCycleComplete() public {
        yieldToken.mint(address(distribution), 1000 ether);
        
        vm.expectRevert(BreadKitDistribution.DistributionNotResolved.selector);
        distribution.distributeYield();
    }
    
    function testCannotDistributeWithoutYield() public {
        vm.roll(block.number + CYCLE_LENGTH + 1);
        
        vm.expectRevert(BreadKitDistribution.InsufficientYield.selector);
        distribution.distributeYield();
    }
    
    function testEmergencyPause() public {
        vm.prank(emergencyAdmin);
        distribution.emergencyPause();
        
        assertTrue(distribution.paused());
        
        yieldToken.mint(address(distribution), 1000 ether);
        vm.roll(block.number + CYCLE_LENGTH + 1);
        
        vm.expectRevert();
        distribution.distributeYield();
    }
    
    function testEmergencyResume() public {
        vm.prank(emergencyAdmin);
        distribution.emergencyPause();
        
        assertTrue(distribution.paused());
        
        distribution.emergencyResume();
        
        assertFalse(distribution.paused());
    }
    
    function testEmergencyWithdraw() public {
        uint256 amount = 1000 ether;
        yieldToken.mint(address(distribution), amount);
        
        vm.prank(emergencyAdmin);
        distribution.emergencyPause();
        
        uint256 balanceBefore = yieldToken.balanceOf(owner);
        
        distribution.emergencyWithdraw(address(yieldToken), owner, amount);
        
        uint256 balanceAfter = yieldToken.balanceOf(owner);
        assertEq(balanceAfter - balanceBefore, amount);
    }
    
    function testValidateDistribution() public {
        (bool canDistribute, string memory reason) = distribution.validateDistribution();
        assertFalse(canDistribute);
        assertEq(reason, "Cycle not complete");
        
        vm.roll(block.number + CYCLE_LENGTH + 1);
        
        (canDistribute, reason) = distribution.validateDistribution();
        assertFalse(canDistribute);
        assertEq(reason, "No yield available");
        
        yieldToken.mint(address(distribution), 1000 ether);
        
        (canDistribute, reason) = distribution.validateDistribution();
        assertTrue(canDistribute);
        assertEq(reason, "");
    }
    
    function testGetCurrentDistributionState() public {
        yieldToken.mint(address(distribution), 1000 ether);
        
        IDistributionModule.DistributionState memory state = distribution.getCurrentDistributionState();
        
        assertEq(state.totalYield, 1000 ether);
        assertEq(state.fixedAmount, 250 ether);
        assertEq(state.votedAmount, 750 ether);
        assertEq(state.totalVotes, 1000);
        assertEq(state.lastDistributionBlock, distribution.lastDistributionBlock());
        assertEq(state.cycleNumber, 0);
    }
    
    function testEmergencyAddRecipient() public {
        address newRecipient = address(0x999);
        
        distribution.emergencyAddRecipient(newRecipient);
        
        address[] memory recipients = recipientRegistry.getActiveRecipients();
        bool found = false;
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == newRecipient) {
                found = true;
                break;
            }
        }
        assertTrue(found);
    }
    
    function testEmergencyRemoveRecipient() public {
        distribution.emergencyRemoveRecipient(recipient2);
        
        address[] memory recipients = recipientRegistry.getActiveRecipients();
        for (uint256 i = 0; i < recipients.length; i++) {
            assertNotEq(recipients[i], recipient2);
        }
    }
    
    function testForceDistribution() public {
        yieldToken.mint(address(distribution), 1000 ether);
        
        distribution.forceDistribution();
        
        assertGt(yieldToken.balanceOf(recipient1), 0);
        assertGt(yieldToken.balanceOf(recipient2), 0);
        assertGt(yieldToken.balanceOf(recipient3), 0);
    }
    
    function testDistributionHistory() public {
        yieldToken.mint(address(distribution), 1000 ether);
        vm.roll(block.number + CYCLE_LENGTH + 1);
        
        distribution.distributeYield();
        
        IDistributionModule.DistributionState memory history = distribution.getDistributionHistory(1);
        
        assertEq(history.totalYield, 1000 ether);
        assertEq(history.totalVotes, 1000);
        assertEq(history.cycleNumber, 1);
        assertEq(history.recipients.length, 3);
    }
    
    function testReadinessStatus() public {
        (bool ready, string memory details) = distribution.getReadinessStatus();
        assertFalse(ready);
        assertEq(details, "Cycle not complete");
        
        vm.roll(block.number + CYCLE_LENGTH + 1);
        
        (ready, details) = distribution.getReadinessStatus();
        assertFalse(ready);
        assertEq(details, "No yield available");
        
        yieldToken.mint(address(distribution), 1000 ether);
        
        (ready, details) = distribution.getReadinessStatus();
        assertTrue(ready);
        assertEq(details, "Ready for distribution");
    }
    
    function testMultipleCycles() public {
        for (uint256 i = 0; i < 3; i++) {
            yieldToken.mint(address(distribution), 1000 ether);
            vm.roll(block.number + CYCLE_LENGTH + 1);
            
            distribution.distributeYield();
            
            assertEq(distribution.cycleNumber(), i + 1);
            assertEq(distribution.lastDistributionBlock(), block.number);
        }
        
        assertEq(yieldToken.balanceOf(recipient1), 1050 ether);
        assertEq(yieldToken.balanceOf(recipient2), 1500 ether);
        assertEq(yieldToken.balanceOf(recipient3), 450 ether);
    }
    
    function testZeroVotesScenario() public {
        votingModule.setVotes([uint256(0), uint256(0), uint256(0)]);
        
        yieldToken.mint(address(distribution), 1000 ether);
        vm.roll(block.number + CYCLE_LENGTH + 1);
        
        (bool canDistribute,) = distribution.validateDistribution();
        assertFalse(canDistribute);
    }
    
    function testDifferentSplitDivisors() public {
        distribution.setYieldFixedSplitDivisor(2);
        
        yieldToken.mint(address(distribution), 1000 ether);
        vm.roll(block.number + CYCLE_LENGTH + 1);
        
        distribution.distributeYield();
        
        uint256 totalDistributed = yieldToken.balanceOf(recipient1) +
                                   yieldToken.balanceOf(recipient2) +
                                   yieldToken.balanceOf(recipient3);
        
        assertEq(totalDistributed, 1000 ether);
    }
}