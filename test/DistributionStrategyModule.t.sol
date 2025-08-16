// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DistributionStrategyModule} from "../src/modules/DistributionStrategyModule.sol";
import {StrategyCalculator} from "../src/modules/StrategyCalculator.sol";
import {IDistributionStrategyModule} from "../src/interfaces/IDistributionStrategyModule.sol";

contract DistributionStrategyModuleTest is Test {
    DistributionStrategyModule public strategyModule;

    address public owner = address(0x1);

    event DistributionStrategyUpdated(uint256 oldDivisor, uint256 newDivisor);

    function setUp() public {
        vm.startPrank(owner);
        strategyModule = new DistributionStrategyModule(2); // 50/50 split default
        vm.stopPrank();
    }

    function testInitialConfiguration() public view {
        assertEq(strategyModule.strategyDivisor(), 2);
        assertEq(strategyModule.owner(), owner);
    }

    function testCalculateDistribution() public view {
        uint256 totalYield = 1000 ether;

        (uint256 fixedAmount, uint256 votedAmount) = strategyModule.calculateDistribution(totalYield);

        assertEq(fixedAmount, 500 ether);
        assertEq(votedAmount, 500 ether);
        assertEq(fixedAmount + votedAmount, totalYield);
    }

    function testCalculateDistributionWithDifferentDivisors() public {
        vm.startPrank(owner);

        uint256 totalYield = 1000 ether;

        // Test 25/75 split (divisor = 4)
        strategyModule.updateDistributionStrategy(4);
        (uint256 fixedAmount, uint256 votedAmount) = strategyModule.calculateDistribution(totalYield);
        assertEq(fixedAmount, 250 ether);
        assertEq(votedAmount, 750 ether);

        // Test 10/90 split (divisor = 10)
        strategyModule.updateDistributionStrategy(10);
        (fixedAmount, votedAmount) = strategyModule.calculateDistribution(totalYield);
        assertEq(fixedAmount, 100 ether);
        assertEq(votedAmount, 900 ether);

        // Test 33/67 split (divisor = 3)
        strategyModule.updateDistributionStrategy(3);
        (fixedAmount, votedAmount) = strategyModule.calculateDistribution(totalYield);
        assertEq(fixedAmount, 333333333333333333333); // ~333.33 ether
        assertEq(votedAmount, 666666666666666666667); // ~666.67 ether

        vm.stopPrank();
    }

    function testUpdateDistributionStrategy() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, false, true);
        emit DistributionStrategyUpdated(2, 3);

        strategyModule.updateDistributionStrategy(3);
        assertEq(strategyModule.strategyDivisor(), 3);

        vm.stopPrank();
    }

    function testUpdateDistributionStrategyRevertConditions() public {
        vm.startPrank(owner);

        // Test zero divisor
        vm.expectRevert(DistributionStrategyModule.InvalidDivisor.selector);
        strategyModule.updateDistributionStrategy(0);

        vm.stopPrank();

        // Test non-owner call
        vm.expectRevert();
        strategyModule.updateDistributionStrategy(3);
    }

    function testValidateStrategyConfiguration() public view {
        assertTrue(strategyModule.validateStrategyConfiguration());
    }

    function testCalculateDistributionWithZeroYield() public view {
        (uint256 fixedAmount, uint256 votedAmount) = strategyModule.calculateDistribution(0);
        assertEq(fixedAmount, 0);
        assertEq(votedAmount, 0);
    }

    function testCalculateDistributionWithSmallAmounts() public {
        vm.startPrank(owner);

        // Test with divisor = 2 and small amount
        uint256 totalYield = 100;
        (uint256 fixedAmount, uint256 votedAmount) = strategyModule.calculateDistribution(totalYield);
        assertEq(fixedAmount, 50);
        assertEq(votedAmount, 50);

        // Test with divisor = 3 and amount that doesn't divide evenly
        strategyModule.updateDistributionStrategy(3);
        totalYield = 10;
        (fixedAmount, votedAmount) = strategyModule.calculateDistribution(totalYield);
        assertEq(fixedAmount, 3); // 10 / 3 = 3 (integer division)
        assertEq(votedAmount, 7); // 10 - 3 = 7

        vm.stopPrank();
    }

    function testStrategyCalculatorLibrary() public pure {
        uint256 totalAmount = 1000 ether;
        uint256 divisor = 4;

        (uint256 fixedAmount, uint256 votedAmount) = StrategyCalculator.calculateSplit(totalAmount, divisor);

        assert(fixedAmount == 250 ether);
        assert(votedAmount == 750 ether);

        // Test percentage calculations
        uint256[] memory percentages = new uint256[](3);
        percentages[0] = 5000; // 50%
        percentages[1] = 3000; // 30%
        percentages[2] = 2000; // 20%

        uint256[] memory shares = StrategyCalculator.calculateRecipientShares(fixedAmount, percentages);

        assert(shares[0] == 125 ether);
        assert(shares[1] == 75 ether);
        assert(shares[2] == 50 ether);

        assert(StrategyCalculator.validatePercentages(percentages) == true);

        // Test invalid percentages
        percentages[2] = 1000; // Now totals 90%
        assert(StrategyCalculator.validatePercentages(percentages) == false);
    }

    function testFuzzCalculateDistribution(uint256 totalYield, uint256 divisor) public {
        // Bound inputs to reasonable ranges
        totalYield = bound(totalYield, 0, 1000000 ether);
        divisor = bound(divisor, 1, 100);

        vm.prank(owner);
        strategyModule.updateDistributionStrategy(divisor);

        (uint256 fixedAmount, uint256 votedAmount) = strategyModule.calculateDistribution(totalYield);

        // Verify invariants
        assertEq(fixedAmount + votedAmount, totalYield, "Sum should equal total");
        assertEq(fixedAmount, totalYield / divisor, "Fixed amount calculation");
        assertLe(fixedAmount, totalYield, "Fixed amount should not exceed total");
    }
}
