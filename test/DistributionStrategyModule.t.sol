// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DistributionStrategyModule} from "../src/modules/DistributionStrategyModule.sol";
import {IDistributionStrategyModule} from "../src/interfaces/IDistributionStrategyModule.sol";
import {IDistributionStrategy} from "../src/interfaces/IDistributionStrategy.sol";
import {EqualDistributionStrategy} from "../src/modules/strategies/EqualDistributionStrategy.sol";
import {VotingDistributionStrategy} from "../src/modules/strategies/VotingDistributionStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

contract DistributionStrategyModuleTest is Test {
    DistributionStrategyModule public strategyModule;
    EqualDistributionStrategy public equalStrategy;
    VotingDistributionStrategy public votingStrategy;
    MockERC20 public yieldToken;

    address public owner = address(0x1);
    address public votingModule = address(0x2);
    address public project1 = address(0x10);
    address public project2 = address(0x11);
    address public project3 = address(0x12);

    event SplitRatioUpdated(uint256 oldDivisor, uint256 newDivisor);
    event StrategiesUpdated(address equalStrategy, address votingStrategy);
    event YieldDistributed(uint256 totalYield, uint256 equalAmount, uint256 votingAmount);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock token
        yieldToken = new MockERC20();

        // Deploy strategies
        equalStrategy = new EqualDistributionStrategy(address(yieldToken));
        votingStrategy = new VotingDistributionStrategy(address(yieldToken), votingModule);

        // Deploy strategy module
        strategyModule = new DistributionStrategyModule(address(yieldToken), 2); // 50/50 split default
        strategyModule.setStrategies(address(equalStrategy), address(votingStrategy));

        // Setup projects for strategies
        address[] memory projects = new address[](3);
        projects[0] = project1;
        projects[1] = project2;
        projects[2] = project3;

        equalStrategy.setProjects(projects);
        votingStrategy.setProjects(projects);

        vm.stopPrank();
    }

    function testInitialConfiguration() public view {
        assertEq(strategyModule.splitDivisor(), 2);
        assertEq(strategyModule.owner(), owner);
        assertEq(address(strategyModule.equalDistributionStrategy()), address(equalStrategy));
        assertEq(address(strategyModule.votingDistributionStrategy()), address(votingStrategy));
    }

    function testCalculateSplit() public view {
        uint256 totalYield = 1000 ether;

        (uint256 equalAmount, uint256 votingAmount) = strategyModule.calculateSplit(totalYield);

        assertEq(equalAmount, 500 ether);
        assertEq(votingAmount, 500 ether);
        assertEq(equalAmount + votingAmount, totalYield);
    }

    function testCalculateSplitWithDifferentDivisors() public {
        vm.startPrank(owner);

        uint256 totalYield = 1000 ether;

        // Test 25/75 split (divisor = 4)
        strategyModule.updateSplitRatio(4);
        (uint256 equalAmount, uint256 votingAmount) = strategyModule.calculateSplit(totalYield);
        assertEq(equalAmount, 250 ether);
        assertEq(votingAmount, 750 ether);

        // Test 10/90 split (divisor = 10)
        strategyModule.updateSplitRatio(10);
        (equalAmount, votingAmount) = strategyModule.calculateSplit(totalYield);
        assertEq(equalAmount, 100 ether);
        assertEq(votingAmount, 900 ether);

        // Test 33/67 split (divisor = 3)
        strategyModule.updateSplitRatio(3);
        (equalAmount, votingAmount) = strategyModule.calculateSplit(totalYield);
        assertEq(equalAmount, 333333333333333333333); // ~333.33 ether
        assertEq(votingAmount, 666666666666666666667); // ~666.67 ether

        vm.stopPrank();
    }

    function testUpdateSplitRatio() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, false, true);
        emit SplitRatioUpdated(2, 3);

        strategyModule.updateSplitRatio(3);
        assertEq(strategyModule.splitDivisor(), 3);

        vm.stopPrank();
    }

    function testUpdateSplitRatioRevertConditions() public {
        vm.startPrank(owner);

        // Test zero divisor
        vm.expectRevert(DistributionStrategyModule.InvalidDivisor.selector);
        strategyModule.updateSplitRatio(0);

        vm.stopPrank();

        // Test non-owner call
        vm.expectRevert();
        strategyModule.updateSplitRatio(3);
    }

    function testSetStrategies() public {
        vm.startPrank(owner);

        address newEqual = address(0x100);
        address newVoting = address(0x101);

        vm.expectEmit(true, true, false, true);
        emit StrategiesUpdated(newEqual, newVoting);

        strategyModule.setStrategies(newEqual, newVoting);

        assertEq(address(strategyModule.equalDistributionStrategy()), newEqual);
        assertEq(address(strategyModule.votingDistributionStrategy()), newVoting);

        vm.stopPrank();
    }

    function testCalculateSplitWithZeroYield() public view {
        (uint256 equalAmount, uint256 votingAmount) = strategyModule.calculateSplit(0);
        assertEq(equalAmount, 0);
        assertEq(votingAmount, 0);
    }

    function testCalculateSplitWithSmallAmounts() public {
        vm.startPrank(owner);

        // Test with divisor = 2 and small amount
        uint256 totalYield = 100;
        (uint256 equalAmount, uint256 votingAmount) = strategyModule.calculateSplit(totalYield);
        assertEq(equalAmount, 50);
        assertEq(votingAmount, 50);

        // Test with divisor = 3 and amount that doesn't divide evenly
        strategyModule.updateSplitRatio(3);
        totalYield = 10;
        (equalAmount, votingAmount) = strategyModule.calculateSplit(totalYield);
        assertEq(equalAmount, 3); // 10 / 3 = 3 (integer division)
        assertEq(votingAmount, 7); // 10 - 3 = 7

        vm.stopPrank();
    }

    function testDistributeYield() public {
        vm.startPrank(owner);

        uint256 totalYield = 1000 ether;
        yieldToken.mint(address(strategyModule), totalYield);

        // Mock voting distribution with some votes
        uint256[] memory votes = new uint256[](3);
        votes[0] = 100;
        votes[1] = 200;
        votes[2] = 300;
        vm.mockCall(votingModule, abi.encodeWithSignature("getCurrentVotingDistribution()"), abi.encode(votes));

        vm.expectEmit(true, true, true, true);
        emit YieldDistributed(totalYield, 500 ether, 500 ether);

        strategyModule.distributeYield(totalYield);

        // Verify tokens were distributed to projects
        // Equal distribution: 500 ether / 3 projects = 166.666... ether each (with remainder to last)
        uint256 equalPerProject = uint256(500 ether) / 3;

        // For voting distribution: project1 gets 100/600, project2 gets 200/600, project3 gets 300/600
        uint256 votingProject1 = (uint256(500 ether) * 100) / 600;
        uint256 votingProject2 = (uint256(500 ether) * 200) / 600;

        // Total balances
        assertEq(yieldToken.balanceOf(project1), equalPerProject + votingProject1);
        assertEq(yieldToken.balanceOf(project2), equalPerProject + votingProject2);

        // Project3 gets remainders from both distributions
        uint256 equalRemainder = uint256(500 ether) - (equalPerProject * 2);
        uint256 votingRemainder = uint256(500 ether) - votingProject1 - votingProject2;
        assertEq(yieldToken.balanceOf(project3), equalRemainder + votingRemainder);

        // Verify strategies have no balance left
        assertEq(yieldToken.balanceOf(address(equalStrategy)), 0);
        assertEq(yieldToken.balanceOf(address(votingStrategy)), 0);

        vm.stopPrank();
    }

    function testFuzzCalculateSplit(uint256 totalYield, uint256 divisor) public {
        // Bound inputs to reasonable ranges
        totalYield = bound(totalYield, 0, 1000000 ether);
        divisor = bound(divisor, 1, 100);

        vm.prank(owner);
        strategyModule.updateSplitRatio(divisor);

        (uint256 equalAmount, uint256 votingAmount) = strategyModule.calculateSplit(totalYield);

        // Verify invariants
        assertEq(equalAmount + votingAmount, totalYield, "Sum should equal total");
        assertEq(equalAmount, totalYield / divisor, "Equal amount calculation");
        assertLe(equalAmount, totalYield, "Equal amount should not exceed total");
    }
}
