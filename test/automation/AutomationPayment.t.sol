// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/modules/automation/ChainlinkAutomationWithPayment.sol";
import "../../src/modules/automation/GelatoAutomationWithPayment.sol";
import "../../src/modules/EnhancedDistributionManager.sol";
import "../../src/interfaces/IYieldModule.sol";
import "../../src/interfaces/IDistributionModule.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock implementations for testing
contract MockYieldToken is ERC20 {
    constructor() ERC20("Mock Yield", "MYT") {
        _mint(msg.sender, 1000000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockYieldModule is IYieldModule {
    MockYieldToken public token;
    uint256 public mockYieldAccrued;

    constructor(address _token) {
        token = MockYieldToken(_token);
    }

    function mint(uint256 amount, address receiver) external override {
        token.mint(receiver, amount);
    }

    function burn(uint256 amount, address receiver) external override {
        // Mock implementation
    }

    function claimYield(uint256 amount, address receiver) external override {
        require(amount <= mockYieldAccrued, "Insufficient yield");
        mockYieldAccrued -= amount;
        token.mint(receiver, amount);
    }

    function yieldAccrued() external view override returns (uint256) {
        return mockYieldAccrued;
    }

    function setYieldAccrued(uint256 amount) external {
        mockYieldAccrued = amount;
    }
}

contract MockDistributionModule is IDistributionModule {
    uint256 public distributeCallCount;
    bool public isPaused;
    uint256 public receivedYield;
    IERC20 public yieldToken;
    
    function setYieldToken(address _token) external {
        yieldToken = IERC20(_token);
    }

    function distributeYield() external override {
        distributeCallCount++;
        // Record received yield if token is set
        if (address(yieldToken) != address(0)) {
            receivedYield = yieldToken.balanceOf(address(this));
        }
    }

    function getCurrentDistributionState() external view override returns (DistributionState memory state) {
        address[] memory recipients = new address[](3);
        uint256[] memory votedDist = new uint256[](3);
        uint256[] memory fixedDist = new uint256[](3);

        state = DistributionState({
            totalYield: 100,
            fixedAmount: 20,
            votedAmount: 80,
            totalVotes: 100,
            lastDistributionBlock: block.number - 100,
            cycleNumber: 1,
            recipients: recipients,
            votedDistributions: votedDist,
            fixedDistributions: fixedDist
        });
    }

    function validateDistribution() external view override returns (bool canDistribute, string memory reason) {
        if (isPaused) {
            return (false, "System is paused");
        }
        return (true, "");
    }

    function emergencyPause() external override {
        isPaused = true;
    }

    function emergencyResume() external override {
        isPaused = false;
    }

    function setCycleLength(uint256) external override {}
    function setYieldFixedSplitDivisor(uint256) external override {}
}

contract AutomationPaymentTest is Test {
    MockYieldToken public yieldToken;
    MockYieldModule public yieldModule;
    MockDistributionModule public distributionModule;
    EnhancedDistributionManager public distributionManager;
    ChainlinkAutomationWithPayment public chainlinkAutomation;
    GelatoAutomationWithPayment public gelatoAutomation;

    address public owner = address(this);
    address public chainlinkTreasury = address(0x1234);
    address public gelatoTreasury = address(0x5678);
    address public keeper = address(0x9999);

    uint256 constant CYCLE_LENGTH = 100;
    uint256 constant MIN_YIELD = 1000 * 10**18;
    uint256 constant FIXED_FEE = 50 * 10**18;
    uint256 constant PERCENTAGE_FEE = 500; // 5%

    event AutomationPaymentMade(
        address indexed provider,
        address indexed receiver,
        uint256 amount,
        uint256 yieldAmount
    );

    event DistributionExecuted(
        uint256 blockNumber,
        uint256 totalYield,
        uint256 automationPayment,
        uint256 distributedYield
    );

    function setUp() public {
        // Deploy mock tokens and modules
        yieldToken = new MockYieldToken();
        yieldModule = new MockYieldModule(address(yieldToken));
        distributionModule = new MockDistributionModule();
        distributionModule.setYieldToken(address(yieldToken));

        // Deploy enhanced distribution manager
        distributionManager = new EnhancedDistributionManager(
            address(distributionModule),
            address(yieldModule),
            address(yieldToken),
            CYCLE_LENGTH,
            MIN_YIELD
        );

        // Deploy Chainlink automation with payment
        chainlinkAutomation = new ChainlinkAutomationWithPayment(
            address(distributionManager),
            address(yieldToken),
            chainlinkTreasury,
            FIXED_FEE,
            PERCENTAGE_FEE,
            MIN_YIELD + FIXED_FEE
        );

        // Deploy Gelato automation with payment
        gelatoAutomation = new GelatoAutomationWithPayment(
            address(distributionManager),
            address(yieldToken),
            gelatoTreasury,
            FIXED_FEE,
            PERCENTAGE_FEE,
            MIN_YIELD + FIXED_FEE
        );

        // Set automation provider in distribution manager
        distributionManager.setAutomationProvider(address(chainlinkAutomation));
    }

    function testPaymentCalculation() public view {
        uint256 yieldAmount = 2000 * 10**18;
        
        (uint256 payment, uint256 remaining) = chainlinkAutomation.calculatePayment(yieldAmount);
        
        // Fixed fee + 5% of yield
        uint256 expectedPayment = FIXED_FEE + (yieldAmount * PERCENTAGE_FEE / 10000);
        assertEq(payment, expectedPayment);
        assertEq(remaining, yieldAmount - expectedPayment);
    }

    function testSufficientYieldCheck() public view {
        // Test with insufficient yield
        uint256 insufficientYield = 500 * 10**18;
        (bool sufficient, uint256 required) = chainlinkAutomation.hasSufficientYield(insufficientYield);
        assertFalse(sufficient);
        assertEq(required, MIN_YIELD + FIXED_FEE);

        // Test with sufficient yield
        uint256 sufficientYield = 2000 * 10**18;
        (sufficient, required) = chainlinkAutomation.hasSufficientYield(sufficientYield);
        assertTrue(sufficient);
    }

    function testDistributionWithInsufficientYield() public {
        // Set yield below threshold
        yieldModule.setYieldAccrued(500 * 10**18);
        
        // Advance blocks
        vm.roll(block.number + CYCLE_LENGTH + 1);

        // Check distribution is not ready
        bool ready = distributionManager.isDistributionReady();
        assertFalse(ready);

        // Try to execute - should revert
        vm.expectRevert();
        chainlinkAutomation.executeDistribution();
    }

    function testSuccessfulDistributionWithPayment() public {
        // Set sufficient yield
        uint256 totalYield = 2000 * 10**18;
        yieldModule.setYieldAccrued(totalYield);

        // Advance blocks
        vm.roll(block.number + CYCLE_LENGTH + 1);

        // Check distribution is ready
        bool ready = distributionManager.isDistributionReady();
        assertTrue(ready);

        // Check upkeep for Chainlink
        (bool upkeepNeeded,) = chainlinkAutomation.checkUpkeep("");
        assertTrue(upkeepNeeded);

        // Execute distribution
        vm.prank(keeper);
        chainlinkAutomation.performUpkeep("");

        // Verify distribution was called
        assertEq(distributionModule.distributeCallCount(), 1);

        // Verify payment was made to chainlink treasury
        uint256 expectedPayment = FIXED_FEE + (totalYield * PERCENTAGE_FEE / 10000);
        assertEq(yieldToken.balanceOf(chainlinkTreasury), expectedPayment);

        // Verify remaining yield went to distribution module
        uint256 expectedDistribution = totalYield - expectedPayment;
        assertApproxEqAbs(distributionModule.receivedYield(), expectedDistribution, 1);
    }

    function testGelatoAutomation() public {
        // Switch to Gelato provider
        distributionManager.setAutomationProvider(address(gelatoAutomation));

        // Set sufficient yield
        uint256 totalYield = 2000 * 10**18;
        yieldModule.setYieldAccrued(totalYield);

        // Advance blocks
        vm.roll(block.number + CYCLE_LENGTH + 1);

        // Check Gelato checker
        (bool canExec, bytes memory execPayload) = gelatoAutomation.checker();
        assertTrue(canExec);
        assertGt(execPayload.length, 0);

        // Execute via Gelato
        vm.prank(keeper);
        gelatoAutomation.execute("");

        // Verify payment was made to gelato treasury
        uint256 expectedPayment = FIXED_FEE + (totalYield * PERCENTAGE_FEE / 10000);
        assertEq(yieldToken.balanceOf(gelatoTreasury), expectedPayment);
    }

    function testDisablePaymentRequirement() public {
        // Disable payment requirement
        chainlinkAutomation.setPaymentRequired(false);

        // Also need to lower the minimum yield requirement in distribution manager
        distributionManager.setMinYieldRequired(500 * 10**18);

        // Set yield (can be lower now)
        uint256 totalYield = 800 * 10**18;
        yieldModule.setYieldAccrued(totalYield);

        // Advance blocks
        vm.roll(block.number + CYCLE_LENGTH + 1);

        // Should be ready even with lower yield
        bool ready = distributionManager.isDistributionReady();
        assertTrue(ready);

        // Execute distribution
        vm.prank(keeper);
        chainlinkAutomation.performUpkeep("");

        // No payment should be made
        assertEq(yieldToken.balanceOf(chainlinkTreasury), 0);

        // All yield should go to distribution
        assertEq(distributionModule.receivedYield(), totalYield);
    }

    function testUpdatePaymentConfig() public {
        // Update payment configuration
        IAutomationPaymentProvider.PaymentConfig memory newConfig = IAutomationPaymentProvider.PaymentConfig({
            requiresPayment: true,
            fixedFee: 100 * 10**18,
            percentageFee: 1000, // 10%
            minYieldThreshold: 1500 * 10**18,
            paymentReceiver: address(0xABCD),
            maxFeeCap: 200 * 10**18
        });

        chainlinkAutomation.updatePaymentConfig(newConfig);

        // Verify new config
        IAutomationPaymentProvider.PaymentConfig memory config = chainlinkAutomation.getPaymentConfig();
        assertEq(config.fixedFee, 100 * 10**18);
        assertEq(config.percentageFee, 1000);
        assertEq(config.maxFeeCap, 200 * 10**18);
    }

    function testMaxFeeCap() public {
        // Set a max fee cap
        IAutomationPaymentProvider.PaymentConfig memory config = chainlinkAutomation.getPaymentConfig();
        config.maxFeeCap = 100 * 10**18;
        chainlinkAutomation.updatePaymentConfig(config);

        // Calculate payment with large yield
        uint256 largeYield = 10000 * 10**18;
        (uint256 payment,) = chainlinkAutomation.calculatePayment(largeYield);

        // Payment should be capped
        assertEq(payment, 100 * 10**18);
    }

    function testDistributionReadinessInfo() public {
        // Set yield below threshold
        yieldModule.setYieldAccrued(500 * 10**18);

        (bool ready, string memory reason, uint256 available, uint256 required) = 
            distributionManager.getDistributionReadiness();

        assertFalse(ready);
        assertEq(available, 500 * 10**18);
        assertTrue(required >= MIN_YIELD);
        assertTrue(bytes(reason).length > 0);
    }

    function testCycleInfo() public {
        (uint256 cycleNumber, uint256 startBlock, uint256 endBlock, uint256 blocksRemaining) = 
            distributionManager.getCycleInfo();

        assertEq(cycleNumber, 1);
        assertEq(startBlock, block.number);
        assertEq(endBlock, block.number + CYCLE_LENGTH);
        assertEq(blocksRemaining, CYCLE_LENGTH);

        // Advance and execute
        yieldModule.setYieldAccrued(2000 * 10**18);
        vm.roll(block.number + CYCLE_LENGTH + 1);
        chainlinkAutomation.executeDistribution();

        // Check updated info
        (cycleNumber, startBlock, endBlock, blocksRemaining) = distributionManager.getCycleInfo();
        assertEq(cycleNumber, 2);
    }

    function testEmergencyPause() public {
        // Set up valid distribution conditions
        yieldModule.setYieldAccrued(2000 * 10**18);
        vm.roll(block.number + CYCLE_LENGTH + 1);

        // Pause the system
        distributionManager.pause();

        // Distribution should not be ready
        bool ready = distributionManager.isDistributionReady();
        assertFalse(ready);

        // Unpause
        distributionManager.unpause();

        // Should be ready again
        ready = distributionManager.isDistributionReady();
        assertTrue(ready);
    }

    function testMultipleProvidersWithDifferentFees() public {
        // Create provider with different fee structure
        GelatoAutomationWithPayment customProvider = new GelatoAutomationWithPayment(
            address(distributionManager),
            address(yieldToken),
            address(0xC5704),
            25 * 10**18, // Lower fixed fee
            1000, // Higher percentage (10%)
            800 * 10**18 // Lower threshold
        );

        // Compare payment calculations
        uint256 yieldAmount = 2000 * 10**18;
        
        (uint256 chainlinkPayment,) = chainlinkAutomation.calculatePayment(yieldAmount);
        (uint256 customPayment,) = customProvider.calculatePayment(yieldAmount);

        // Chainlink: 50 + (2000 * 5%) = 50 + 100 = 150
        assertEq(chainlinkPayment, 150 * 10**18);
        
        // Custom: 25 + (2000 * 10%) = 25 + 200 = 225
        assertEq(customPayment, 225 * 10**18);
    }
}