// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DistributionManager} from "../src/modules/DistributionManager.sol";
import {IDistributionModule} from "../src/interfaces/IDistributionModule.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Simple concrete implementation for testing
contract TestDistribution is DistributionManager {
    function initialize(
        address _yieldToken,
        address _yieldSource,
        uint256 _cycleLength,
        uint256 _yieldFixedSplitDivisor
    ) external {
        __DistributionManager_init(_yieldToken, _yieldSource, _cycleLength, _yieldFixedSplitDivisor);
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

    // No need to override _mintTokensBeforeDistribution, _collectYield, or _getAvailableYield
    // They are now concrete implementations in DistributionManager

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
        distribution.initialize(address(yieldToken), address(yieldToken), CYCLE_LENGTH, YIELD_FIXED_SPLIT_DIVISOR);

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

    function testPrecisionValidationMinimumYield() public {
        // Test that yield must be at least 1 wei per recipient
        yieldToken.mint(address(distribution), 2); // Only 2 wei for 3 recipients
        vm.roll(block.number + CYCLE_LENGTH + 1);

        (bool canDistribute, string memory reason) = distribution.validateDistribution();
        assertFalse(canDistribute);
        assertEq(reason, "Insufficient yield precision for accurate distribution");
    }

    function testPrecisionValidationFixedDistribution() public {
        // Test that fixed distribution can handle minimum amounts
        distribution.setYieldFixedSplitDivisor(2); // 50% fixed, 50% voted

        // With default votes [300, 500, 200] and total 1000, we need enough yield
        // so that smallest vote (200) gets at least 1 wei in voted distribution
        // For 50% voted: smallest distribution = (200 * votedAmount) / 1000 >= 1
        // So votedAmount >= 5, and totalYield >= 10
        yieldToken.mint(address(distribution), 2000); // Plenty for validation
        vm.roll(block.number + CYCLE_LENGTH + 1);

        (bool canDistribute,) = distribution.validateDistribution();
        assertTrue(canDistribute);
    }

    function testPrecisionValidationSmallVoteShares() public {
        // Test very small vote share precision
        uint256[] memory smallVotes = new uint256[](3);
        smallVotes[0] = 1; // Smallest possible vote
        smallVotes[1] = 1000; // Much larger vote
        smallVotes[2] = 999; // Large vote
        distribution.setVotes(smallVotes);

        // With 2000 total votes and small voted amount, check precision
        yieldToken.mint(address(distribution), 4000); // Should be enough
        vm.roll(block.number + CYCLE_LENGTH + 1);

        (bool canDistribute,) = distribution.validateDistribution();
        assertTrue(canDistribute);
    }

    function testPrecisionValidationUnderflowScenario() public {
        // Create scenario where smallest vote would result in 0 distribution
        uint256[] memory votes = new uint256[](3);
        votes[0] = 1; // Extremely small vote
        votes[1] = 1000000; // Very large vote
        votes[2] = 1000000; // Very large vote
        distribution.setVotes(votes);

        // Use minimum yield that would cause underflow in voted distribution
        yieldToken.mint(address(distribution), 10); // Very small yield
        vm.roll(block.number + CYCLE_LENGTH + 1);

        (bool canDistribute, string memory reason) = distribution.validateDistribution();
        assertFalse(canDistribute);
        assertEq(reason, "Insufficient yield precision for accurate distribution");
    }

    function testPrecisionValidationEdgeCase() public {
        // Test edge case where yield is exactly at the threshold
        uint256[] memory votes = new uint256[](3);
        votes[0] = 1;
        votes[1] = 1;
        votes[2] = 1;
        distribution.setVotes(votes);

        // Mint exactly enough yield for minimum distribution
        yieldToken.mint(address(distribution), 6); // 2 * 3 recipients = 6 (considering 50/50 split)
        vm.roll(block.number + CYCLE_LENGTH + 1);

        (bool canDistribute,) = distribution.validateDistribution();
        assertTrue(canDistribute);
    }

    function testPrecisionValidationFailsOnTooSmallYield() public {
        // Test that validation correctly rejects yield amounts that would cause precision issues
        distribution.setYieldFixedSplitDivisor(2); // 50% fixed, 50% voted

        // With default votes [300, 500, 200] and total 1000, 6 wei total is too small
        // Fixed: 3 wei, Voted: 3 wei
        // Smallest vote (200) would get: (200 * 3) / 1000 = 0 wei (precision loss)
        yieldToken.mint(address(distribution), 6);
        vm.roll(block.number + CYCLE_LENGTH + 1);

        (bool canDistribute, string memory reason) = distribution.validateDistribution();
        assertFalse(canDistribute);
        assertEq(reason, "Insufficient yield precision for accurate distribution");
    }
}
