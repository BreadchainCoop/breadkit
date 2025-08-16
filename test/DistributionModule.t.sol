// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DistributionManager} from "../src/modules/DistributionManager.sol";
import {YieldCollector} from "../src/modules/YieldCollector.sol";
import {IDistributionModule} from "../src/interfaces/IDistributionModule.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Simple concrete implementation for testing
contract TestDistribution is DistributionManager {
    function initialize(address _yieldToken, uint256 _cycleLength, uint256 _yieldFixedSplitDivisor) external {
        __DistributionManager_init(_yieldToken, _cycleLength, _yieldFixedSplitDivisor);
    }

    function setRecipients(address[] memory _recipients) external {
        recipients = _recipients;
    }

    function setVotes(uint256[] memory votes) external {
        currentVotes = votes;
        totalVotes = 0;
        for (uint256 i = 0; i < votes.length; i++) {
            totalVotes += votes[i];
        }
    }

    function _mintTokensBeforeDistribution() internal override {
        // Hook implementation - can be customized by inheriting contracts
    }

    function _collectYield() internal override returns (uint256) {
        // Simple implementation: return current balance
        return MockERC20(yieldToken).balanceOf(address(this));
    }

    function _getAvailableYield() internal view override returns (uint256) {
        return MockERC20(yieldToken).balanceOf(address(this));
    }

    function _getVotingResults() internal view override returns (uint256[] memory) {
        return currentVotes;
    }

    function _getActiveRecipients() internal view override returns (address[] memory) {
        return recipients;
    }

    function _processQueuedChanges() internal override {
        // Hook implementation - can be customized by inheriting contracts
    }
}

contract DistributionModuleTest is Test {
    TestDistribution public distribution;
    YieldCollector public yieldCollector;
    MockERC20 public yieldToken;

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
        distribution = new TestDistribution();
        distribution.initialize(address(yieldToken), CYCLE_LENGTH, YIELD_FIXED_SPLIT_DIVISOR);

        distribution.setEmergencyAdmin(emergencyAdmin);

        address[] memory testRecipients = new address[](3);
        testRecipients[0] = recipient1;
        testRecipients[1] = recipient2;
        testRecipients[2] = recipient3;
        distribution.setRecipients(testRecipients);

        uint256[] memory votes = new uint256[](3);
        votes[0] = 300;
        votes[1] = 500;
        votes[2] = 200;
        distribution.setVotes(votes);

        yieldCollector = new YieldCollector(address(yieldToken), address(yieldToken));
        yieldCollector.setDistributionManager(address(distribution));
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

        uint256 totalDistributed = (recipient1BalanceAfter - recipient1BalanceBefore)
            + (recipient2BalanceAfter - recipient2BalanceBefore) + (recipient3BalanceAfter - recipient3BalanceBefore);

        assertEq(totalDistributed, 1000 ether);
    }

    function testDistributionWithFixedAndVotedSplit() public {
        uint256 totalYield = 1000 ether;
        yieldToken.mint(address(distribution), totalYield);

        vm.roll(block.number + CYCLE_LENGTH + 1);

        distribution.distributeYield();

        // Fixed amount should be 1/4 of total (250 ether)
        // Voted amount should be 3/4 of total (750 ether)
        uint256 expectedFixedAmount = totalYield / YIELD_FIXED_SPLIT_DIVISOR;
        uint256 expectedVotedAmount = totalYield - expectedFixedAmount;

        // Each recipient gets equal share of fixed (250/3 = ~83.33 ether)
        uint256 expectedFixedPerRecipient = expectedFixedAmount / 3;

        // Recipient2 gets 50% of voted amount (750 * 0.5 = 375 ether)
        uint256 recipient2VotedAmount = (expectedVotedAmount * 500) / 1000;
        uint256 recipient2Total = expectedFixedPerRecipient + recipient2VotedAmount;

        // Allow for small rounding differences
        assertApproxEqAbs(yieldToken.balanceOf(recipient2), recipient2Total, 3);
    }

    function testCannotDistributeBeforeCycleComplete() public {
        yieldToken.mint(address(distribution), 1000 ether);

        vm.expectRevert(DistributionManager.DistributionNotResolved.selector);
        distribution.distributeYield();
    }

    function testCannotDistributeWithoutYield() public {
        vm.roll(block.number + CYCLE_LENGTH + 1);

        vm.expectRevert(DistributionManager.DistributionNotResolved.selector);
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

    function testMultipleCycles() public {
        for (uint256 i = 0; i < 3; i++) {
            yieldToken.mint(address(distribution), 1000 ether);
            vm.roll(block.number + CYCLE_LENGTH + 1);

            // Reset votes for each cycle
            uint256[] memory votes = new uint256[](3);
            votes[0] = 300;
            votes[1] = 500;
            votes[2] = 200;
            distribution.setVotes(votes);

            distribution.distributeYield();

            assertEq(distribution.cycleNumber(), i + 1);
            assertEq(distribution.lastDistributionBlock(), block.number);
        }

        // Each cycle distributes 1000 ether with same proportions
        // Fixed: 250 ether per cycle (83.33 each)
        // Voted: 750 ether per cycle (30% to r1, 50% to r2, 20% to r3)
        // Total after 3 cycles:
        // r1: 3 * (83.33 + 225) = ~925 ether
        // r2: 3 * (83.33 + 375) = ~1375 ether
        // r3: 3 * (83.33 + 150) = ~700 ether

        assertApproxEqAbs(yieldToken.balanceOf(recipient1), 925 ether, 5 ether);
        assertApproxEqAbs(yieldToken.balanceOf(recipient2), 1375 ether, 5 ether);
        assertApproxEqAbs(yieldToken.balanceOf(recipient3), 700 ether, 5 ether);
    }

    function testZeroVotesScenario() public {
        uint256[] memory zeroVotes = new uint256[](3);
        distribution.setVotes(zeroVotes);

        yieldToken.mint(address(distribution), 1000 ether);
        vm.roll(block.number + CYCLE_LENGTH + 1);

        (bool canDistribute,) = distribution.validateDistribution();
        assertFalse(canDistribute);
    }

    function testDifferentSplitDivisors() public {
        distribution.setYieldFixedSplitDivisor(2); // 50/50 split

        yieldToken.mint(address(distribution), 1000 ether);
        vm.roll(block.number + CYCLE_LENGTH + 1);

        distribution.distributeYield();

        uint256 totalDistributed =
            yieldToken.balanceOf(recipient1) + yieldToken.balanceOf(recipient2) + yieldToken.balanceOf(recipient3);

        assertEq(totalDistributed, 1000 ether);
    }
}
