// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DistributionStrategyModule} from "../src/modules/DistributionStrategyModule.sol";
import {IDistributionStrategyModule} from "../src/interfaces/IDistributionStrategyModule.sol";
import {IDistributionStrategy} from "../src/interfaces/IDistributionStrategy.sol";
import {EqualDistributionStrategy} from "../src/modules/strategies/EqualDistributionStrategy.sol";
import {VotingDistributionStrategy} from "../src/modules/strategies/VotingDistributionStrategy.sol";
import {MockRecipientRegistry} from "./mocks/MockRecipientRegistry.sol";
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
    MockRecipientRegistry public recipientRegistry;
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
        
        // Deploy recipient registry and add recipients
        recipientRegistry = new MockRecipientRegistry();
        address[] memory recipients = new address[](3);
        recipients[0] = project1;
        recipients[1] = project2;
        recipients[2] = project3;
        recipientRegistry.addRecipients(recipients);
        
        // Deploy strategies with recipient registry
        equalStrategy = new EqualDistributionStrategy(address(yieldToken), address(recipientRegistry));
        votingStrategy = new VotingDistributionStrategy(address(yieldToken), address(recipientRegistry), votingModule);
        
        // Deploy strategy module
        strategyModule = new DistributionStrategyModule(address(yieldToken));
        
        // Add strategies to module
        strategyModule.addStrategy(address(equalStrategy));
        strategyModule.addStrategy(address(votingStrategy));
        
        vm.stopPrank();
    }

    function testInitialConfiguration() public view {
        assertEq(strategyModule.owner(), owner);
        assertTrue(strategyModule.isStrategy(address(equalStrategy)));
        assertTrue(strategyModule.isStrategy(address(votingStrategy)));
        
        // Verify registry is set up correctly
        address[] memory registeredRecipients = recipientRegistry.getRecipients();
        assertEq(registeredRecipients.length, 3);
        assertEq(registeredRecipients[0], project1);
        assertEq(registeredRecipients[1], project2);
        assertEq(registeredRecipients[2], project3);
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
        
        // Verify distribution to projects from registry
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
    
    function testDistributeWithVotingStrategy() public {
        vm.startPrank(owner);
        
        uint256 amount = 600 ether;
        yieldToken.mint(address(strategyModule), amount);
        
        // Mock voting distribution with weighted votes
        uint256[] memory votes = new uint256[](3);
        votes[0] = 100;  // project1 gets 100/600 = 1/6
        votes[1] = 200;  // project2 gets 200/600 = 2/6
        votes[2] = 300;  // project3 gets 300/600 = 3/6
        vm.mockCall(
            votingModule, 
            abi.encodeWithSignature("getCurrentVotingDistribution()"),
            abi.encode(votes)
        );
        
        strategyModule.distributeToStrategy(address(votingStrategy), amount);
        
        // Verify weighted distribution to projects
        assertEq(yieldToken.balanceOf(project1), 100 ether); // 600 * 100/600 = 100
        assertEq(yieldToken.balanceOf(project2), 200 ether); // 600 * 200/600 = 200
        assertEq(yieldToken.balanceOf(project3), 300 ether); // 600 * 300/600 = 300
        
        vm.stopPrank();
    }

    function testRegistryUpdate() public {
        vm.startPrank(owner);
        
        // Add a new recipient to registry
        address newProject = address(0x20);
        recipientRegistry.queueRecipientAddition(newProject);
        recipientRegistry.processQueue();
        
        // Verify new recipient is in registry
        address[] memory recipients = recipientRegistry.getRecipients();
        assertEq(recipients.length, 4);
        
        // Distribute to verify all recipients get funds
        uint256 amount = 400 ether;
        yieldToken.mint(address(strategyModule), amount);
        strategyModule.distributeToStrategy(address(equalStrategy), amount);
        
        // Each recipient should get 100 ether (400 / 4)
        assertEq(yieldToken.balanceOf(project1), 100 ether);
        assertEq(yieldToken.balanceOf(project2), 100 ether);
        assertEq(yieldToken.balanceOf(project3), 100 ether);
        assertEq(yieldToken.balanceOf(newProject), 100 ether);
        
        vm.stopPrank();
    }
}