// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DistributionStrategyModule} from "../src/modules/DistributionStrategyModule.sol";
import {StrategyCalculator} from "../src/modules/StrategyCalculator.sol";
import {StrategyRecipientManager} from "../src/modules/StrategyRecipientManager.sol";
import {IDistributionStrategyModule} from "../src/interfaces/IDistributionStrategyModule.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

contract MockYieldToken is ERC20 {
    constructor() ERC20("Mock Yield", "MYIELD") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DistributionStrategyModuleTest is Test {
    DistributionStrategyModule public strategyModule;
    StrategyRecipientManager public recipientManager;
    MockYieldToken public yieldToken;

    address public owner = address(0x1);
    address public authorized = address(0x2);
    address public recipient1 = address(0x3);
    address public recipient2 = address(0x4);
    address public recipient3 = address(0x5);

    uint256 constant PERCENTAGE_BASE = 10000;

    event DistributionStrategyUpdated(uint256 oldDivisor, uint256 newDivisor);
    event StrategyRecipientsUpdated(address[] recipients, uint256[] percentages);
    event StrategyDistribution(address indexed recipient, uint256 amount);
    event StrategyDistributionComplete(uint256 totalAmount, uint256 actualDistributed);

    function setUp() public {
        vm.startPrank(owner);

        yieldToken = new MockYieldToken();
        strategyModule = new DistributionStrategyModule(address(yieldToken), 2); // 50/50 split default
        recipientManager = new StrategyRecipientManager();

        strategyModule.setAuthorized(authorized);

        vm.stopPrank();
    }

    function testInitialConfiguration() public view {
        assertEq(strategyModule.strategyDivisor(), 2);
        assertEq(address(strategyModule.yieldToken()), address(yieldToken));
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

        strategyModule.updateDistributionStrategy(4);
        (uint256 fixedAmount, uint256 votedAmount) = strategyModule.calculateDistribution(totalYield);
        assertEq(fixedAmount, 250 ether);
        assertEq(votedAmount, 750 ether);

        strategyModule.updateDistributionStrategy(10);
        (fixedAmount, votedAmount) = strategyModule.calculateDistribution(totalYield);
        assertEq(fixedAmount, 100 ether);
        assertEq(votedAmount, 900 ether);

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

        vm.expectRevert(DistributionStrategyModule.InvalidDivisor.selector);
        strategyModule.updateDistributionStrategy(0);

        vm.stopPrank();

        vm.expectRevert();
        strategyModule.updateDistributionStrategy(3);
    }

    function testSetStrategyRecipients() public {
        vm.startPrank(owner);

        address[] memory recipients = new address[](3);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        recipients[2] = recipient3;

        uint256[] memory percentages = new uint256[](3);
        percentages[0] = 5000; // 50%
        percentages[1] = 3000; // 30%
        percentages[2] = 2000; // 20%

        vm.expectEmit(true, true, false, true);
        emit StrategyRecipientsUpdated(recipients, percentages);

        strategyModule.setStrategyRecipients(recipients, percentages);

        (address[] memory storedRecipients, uint256[] memory storedPercentages) = strategyModule.getStrategyRecipients();

        assertEq(storedRecipients.length, 3);
        assertEq(storedRecipients[0], recipient1);
        assertEq(storedRecipients[1], recipient2);
        assertEq(storedRecipients[2], recipient3);

        assertEq(storedPercentages[0], 5000);
        assertEq(storedPercentages[1], 3000);
        assertEq(storedPercentages[2], 2000);

        vm.stopPrank();
    }

    function testSetStrategyRecipientsRevertConditions() public {
        vm.startPrank(owner);

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory percentages = new uint256[](3);
        percentages[0] = 5000;
        percentages[1] = 3000;
        percentages[2] = 2000;

        vm.expectRevert(DistributionStrategyModule.LengthMismatch.selector);
        strategyModule.setStrategyRecipients(recipients, percentages);

        address[] memory emptyRecipients = new address[](0);
        uint256[] memory emptyPercentages = new uint256[](0);

        vm.expectRevert(DistributionStrategyModule.EmptyRecipients.selector);
        strategyModule.setStrategyRecipients(emptyRecipients, emptyPercentages);

        recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        percentages = new uint256[](2);
        percentages[0] = 5000;
        percentages[1] = 4000; // Total = 9000, not 10000

        vm.expectRevert(DistributionStrategyModule.InvalidPercentageTotal.selector);
        strategyModule.setStrategyRecipients(recipients, percentages);

        recipients[0] = address(0);
        percentages[1] = 5000;

        vm.expectRevert(DistributionStrategyModule.ZeroAddress.selector);
        strategyModule.setStrategyRecipients(recipients, percentages);

        vm.stopPrank();
    }

    function testDistributeFixed() public {
        vm.startPrank(owner);

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 6000; // 60%
        percentages[1] = 4000; // 40%

        strategyModule.setStrategyRecipients(recipients, percentages);

        uint256 distributeAmount = 1000 ether;
        yieldToken.transfer(address(strategyModule), distributeAmount);

        vm.stopPrank();

        vm.startPrank(authorized);

        uint256 recipient1BalanceBefore = yieldToken.balanceOf(recipient1);
        uint256 recipient2BalanceBefore = yieldToken.balanceOf(recipient2);

        vm.expectEmit(true, true, false, true);
        emit StrategyDistribution(recipient1, 600 ether);
        vm.expectEmit(true, true, false, true);
        emit StrategyDistribution(recipient2, 400 ether);
        vm.expectEmit(true, true, false, true);
        emit StrategyDistributionComplete(1000 ether, 1000 ether);

        strategyModule.distributeFixed(distributeAmount);

        assertEq(yieldToken.balanceOf(recipient1) - recipient1BalanceBefore, 600 ether);
        assertEq(yieldToken.balanceOf(recipient2) - recipient2BalanceBefore, 400 ether);

        vm.stopPrank();
    }

    function testDistributeFixedRevertConditions() public {
        vm.startPrank(authorized);

        vm.expectRevert(DistributionStrategyModule.NoStrategyRecipients.selector);
        strategyModule.distributeFixed(1000 ether);

        vm.stopPrank();

        vm.startPrank(owner);

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 10000;

        strategyModule.setStrategyRecipients(recipients, percentages);

        vm.stopPrank();

        vm.startPrank(authorized);

        vm.expectRevert(DistributionStrategyModule.ZeroFixedAmount.selector);
        strategyModule.distributeFixed(0);

        vm.stopPrank();

        vm.expectRevert(Ownable.Unauthorized.selector);
        strategyModule.distributeFixed(1000 ether);
    }

    function testValidateStrategyConfiguration() public {
        assertTrue(strategyModule.validateStrategyConfiguration());

        vm.startPrank(owner);

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 5000;
        percentages[1] = 5000;

        strategyModule.setStrategyRecipients(recipients, percentages);

        assertTrue(strategyModule.validateStrategyConfiguration());

        vm.stopPrank();
    }

    function testGetStrategyAmount() public view {
        uint256 totalYield = 1000 ether;
        uint256 strategyAmount = strategyModule.getStrategyAmount(totalYield);

        assertEq(strategyAmount, 500 ether);

        strategyAmount = strategyModule.getStrategyAmount(0);
        assertEq(strategyAmount, 0);
    }

    function testStrategyCalculatorLibrary() public pure {
        uint256 totalAmount = 1000 ether;
        uint256 divisor = 4;

        (uint256 fixedAmount, uint256 votedAmount) = StrategyCalculator.calculateSplit(totalAmount, divisor);

        assert(fixedAmount == 250 ether);
        assert(votedAmount == 750 ether);

        uint256[] memory percentages = new uint256[](3);
        percentages[0] = 5000;
        percentages[1] = 3000;
        percentages[2] = 2000;

        uint256[] memory shares = StrategyCalculator.calculateRecipientShares(fixedAmount, percentages);

        assert(shares[0] == 125 ether);
        assert(shares[1] == 75 ether);
        assert(shares[2] == 50 ether);

        assert(StrategyCalculator.validatePercentages(percentages) == true);

        percentages[2] = 1000;
        assert(StrategyCalculator.validatePercentages(percentages) == false);
    }

    function testRecipientManager() public {
        vm.startPrank(owner);

        recipientManager.addRecipient(recipient1, 5000, "Project 1");
        recipientManager.addRecipient(recipient2, 3000, "Project 2");
        recipientManager.addRecipient(recipient3, 2000, "Project 3");

        assertEq(recipientManager.activeRecipientCount(), 3);
        assertTrue(recipientManager.validateRecipients());

        recipientManager.updatePercentage(recipient1, 4000);
        recipientManager.updatePercentage(recipient2, 4000);

        assertTrue(recipientManager.validateRecipients());

        recipientManager.removeRecipient(recipient3);
        assertEq(recipientManager.activeRecipientCount(), 2);
        assertFalse(recipientManager.validateRecipients());

        recipientManager.addRecipient(recipient3, 2000, "Project 3 Updated");
        assertTrue(recipientManager.validateRecipients());

        (address[] memory addresses, uint256[] memory percentages) = recipientManager.getActiveRecipientsData();

        assertEq(addresses.length, 3);
        assertEq(percentages[0], 4000);
        assertEq(percentages[1], 4000);
        assertEq(percentages[2], 2000);

        vm.stopPrank();
    }

    function testIntegrationFlow() public {
        vm.startPrank(owner);

        address[] memory recipients = new address[](3);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        recipients[2] = recipient3;

        uint256[] memory percentages = new uint256[](3);
        percentages[0] = 5000;
        percentages[1] = 3000;
        percentages[2] = 2000;

        strategyModule.setStrategyRecipients(recipients, percentages);
        strategyModule.updateDistributionStrategy(4);

        uint256 totalYield = 2000 ether;
        yieldToken.transfer(address(strategyModule), totalYield);

        (uint256 fixedAmount, uint256 votedAmount) = strategyModule.calculateDistribution(totalYield);

        assertEq(fixedAmount, 500 ether);
        assertEq(votedAmount, 1500 ether);

        vm.stopPrank();

        vm.startPrank(authorized);

        strategyModule.distributeFixed(fixedAmount);

        assertEq(yieldToken.balanceOf(recipient1), 250 ether);
        assertEq(yieldToken.balanceOf(recipient2), 150 ether);
        assertEq(yieldToken.balanceOf(recipient3), 100 ether);

        vm.stopPrank();
    }
}
