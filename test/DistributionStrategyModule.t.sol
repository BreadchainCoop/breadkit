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

    event StrategyAdded(address strategy);
    event StrategyRemoved(address strategy);
    event YieldDistributed(address strategy, uint256 amount);

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy mock token
        yieldToken = new MockERC20();
        
        // Deploy strategies
        equalStrategy = new EqualDistributionStrategy(address(yieldToken));
        votingStrategy = new VotingDistributionStrategy(address(yieldToken), votingModule);
        
        // Deploy strategy module
        strategyModule = new DistributionStrategyModule(address(yieldToken));
        
        // Add strategies to module
        strategyModule.addStrategy(address(equalStrategy));
        strategyModule.addStrategy(address(votingStrategy));
        
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
        assertEq(strategyModule.owner(), owner);
        assertTrue(strategyModule.isStrategy(address(equalStrategy)));
        assertTrue(strategyModule.isStrategy(address(votingStrategy)));
    }

    function testAddStrategy() public {
        vm.startPrank(owner);
        
        address newStrategy = address(0x100);
        
        vm.expectEmit(true, false, false, false);
        emit StrategyAdded(newStrategy);
        
        strategyModule.addStrategy(newStrategy);
        
        assertTrue(strategyModule.isStrategy(newStrategy));
        
        vm.stopPrank();
    }

    function testRemoveStrategy() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, false, false, false);
        emit StrategyRemoved(address(equalStrategy));
        
        strategyModule.removeStrategy(address(equalStrategy));
        
        assertFalse(strategyModule.isStrategy(address(equalStrategy)));
        
        vm.stopPrank();
    }

    function testDistributeToStrategy() public {
        vm.startPrank(owner);
        
        uint256 amount = 300 ether;
        yieldToken.mint(address(strategyModule), amount);
        
        // Mock voting distribution
        uint256[] memory votes = new uint256[](3);
        votes[0] = 100;
        votes[1] = 200;
        votes[2] = 300;
        vm.mockCall(
            votingModule, 
            abi.encodeWithSignature("getCurrentVotingDistribution()"),
            abi.encode(votes)
        );
        
        vm.expectEmit(true, true, false, false);
        emit YieldDistributed(address(equalStrategy), amount);
        
        strategyModule.distributeToStrategy(address(equalStrategy), amount);
        
        // Verify distribution to projects
        assertEq(yieldToken.balanceOf(project1), 100 ether);
        assertEq(yieldToken.balanceOf(project2), 100 ether);
        assertEq(yieldToken.balanceOf(project3), 100 ether);
        
        vm.stopPrank();
    }

    function testGetStrategies() public view {
        address[] memory strategies = strategyModule.getStrategies();
        
        assertEq(strategies.length, 2);
        assertEq(strategies[0], address(equalStrategy));
        assertEq(strategies[1], address(votingStrategy));
    }

    function testCannotAddZeroAddress() public {
        vm.startPrank(owner);
        
        vm.expectRevert(DistributionStrategyModule.ZeroAddress.selector);
        strategyModule.addStrategy(address(0));
        
        vm.stopPrank();
    }

    function testCannotAddDuplicateStrategy() public {
        vm.startPrank(owner);
        
        vm.expectRevert(DistributionStrategyModule.StrategyAlreadyRegistered.selector);
        strategyModule.addStrategy(address(equalStrategy));
        
        vm.stopPrank();
    }

    function testCannotRemoveUnregisteredStrategy() public {
        vm.startPrank(owner);
        
        vm.expectRevert(DistributionStrategyModule.StrategyNotRegistered.selector);
        strategyModule.removeStrategy(address(0x999));
        
        vm.stopPrank();
    }

    function testCannotDistributeToUnregisteredStrategy() public {
        vm.startPrank(owner);
        
        yieldToken.mint(address(strategyModule), 100 ether);
        
        vm.expectRevert(DistributionStrategyModule.StrategyNotRegistered.selector);
        strategyModule.distributeToStrategy(address(0x999), 100 ether);
        
        vm.stopPrank();
    }

    function testCannotDistributeZeroAmount() public {
        vm.startPrank(owner);
        
        vm.expectRevert(DistributionStrategyModule.ZeroAmount.selector);
        strategyModule.distributeToStrategy(address(equalStrategy), 0);
        
        vm.stopPrank();
    }
}