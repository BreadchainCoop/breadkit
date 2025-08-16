// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/modules/automation/ExecutionCoordinator.sol";
import "../../src/interfaces/ICycleManager.sol";
import "../../src/interfaces/IDistributionModule.sol";
import "../../src/interfaces/IAutomation.sol";

contract MockCycleManager is ICycleManager {
    bool public distributionReady = true;
    uint256 public blocksUntilNext = 0;
    uint256 public cycleNumber = 1;
    uint256 public cycleLength = 100;

    function isDistributionReady() external view returns (bool) {
        return distributionReady;
    }

    function getBlocksUntilNextCycle() external view returns (uint256) {
        return blocksUntilNext;
    }

    function startNewCycle() external {
        cycleNumber++;
        blocksUntilNext = cycleLength;
    }

    function getCycleInfo() external view returns (uint256, uint256, uint256) {
        return (cycleNumber, block.number, block.number + blocksUntilNext);
    }

    function setCycleLength(uint256 _cycleLength) external {
        cycleLength = _cycleLength;
    }

    function getCycleLength() external view returns (uint256) {
        return cycleLength;
    }

    function setDistributionReady(bool _ready) external {
        distributionReady = _ready;
    }

    function setBlocksUntilNext(uint256 _blocks) external {
        blocksUntilNext = _blocks;
    }
}

contract MockDistributionModule is IDistributionModule {
    uint256 public distributeCallCount;
    bool public shouldRevert;
    string public revertMessage = "Distribution failed";

    function distribute() external {
        if (shouldRevert) {
            revert(revertMessage);
        }
        distributeCallCount++;
    }

    function getCurrentDistribution() external pure returns (uint256[] memory) {
        uint256[] memory dist = new uint256[](3);
        dist[0] = 40;
        dist[1] = 35;
        dist[2] = 25;
        return dist;
    }

    function setCycleLength(uint256) external {}
    function setYieldFixedSplitDivisor(uint256) external {}
    function setAMMVotingPower(address) external {}

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
}

contract SimpleAutomationProvider is IAutomation {
    ICycleManager public cycleManager;
    bool public isActive = true;
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function checkCondition() external view returns (bool needsExecution, bytes memory performData) {
        if (!isActive) {
            return (false, "Provider inactive");
        }

        if (address(cycleManager) == address(0)) {
            return (false, "No cycle manager");
        }

        if (!cycleManager.isDistributionReady()) {
            return (false, "Distribution not ready");
        }

        return (true, abi.encode("execute"));
    }

    function execute(bytes calldata) external {
        require(isActive, "Provider not active");
    }

    function isProviderActive() external view returns (bool) {
        return isActive;
    }

    function setCycleManager(address _cycleManager) external {
        require(msg.sender == owner, "Unauthorized");
        cycleManager = ICycleManager(_cycleManager);
    }

    function getCycleManager() external view returns (address) {
        return address(cycleManager);
    }

    function setActive(bool _isActive) external {
        require(msg.sender == owner, "Unauthorized");
        isActive = _isActive;
    }
}

contract AutomationModuleSimpleTest is Test {
    ExecutionCoordinator public executionCoordinator;
    MockCycleManager public cycleManager;
    MockDistributionModule public distributionModule;
    SimpleAutomationProvider public provider1;
    SimpleAutomationProvider public provider2;

    address public owner = address(0x1);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock modules
        cycleManager = new MockCycleManager();
        distributionModule = new MockDistributionModule();
        executionCoordinator = new ExecutionCoordinator();

        // Deploy providers
        provider1 = new SimpleAutomationProvider(owner);
        provider2 = new SimpleAutomationProvider(owner);

        // Setup providers
        provider1.setCycleManager(address(cycleManager));
        provider2.setCycleManager(address(cycleManager));

        vm.stopPrank();
    }

    function testExecutionCoordinatorLocking() public {
        // First provider locks
        vm.prank(address(provider1));
        bool locked = executionCoordinator.lockExecution();
        assertTrue(locked);
        assertTrue(executionCoordinator.isExecutionLocked());

        // Second provider cannot lock
        vm.prank(address(provider2));
        bool locked2 = executionCoordinator.lockExecution();
        assertFalse(locked2);

        // First provider unlocks
        vm.prank(address(provider1));
        executionCoordinator.unlockExecution();
        assertFalse(executionCoordinator.isExecutionLocked());

        // Now second provider can lock
        vm.prank(address(provider2));
        bool locked3 = executionCoordinator.lockExecution();
        assertTrue(locked3);
    }

    function testExecutionHistory() public {
        // Lock execution
        vm.prank(address(provider1));
        executionCoordinator.lockExecution();

        uint256 currentId = executionCoordinator.currentExecutionId();
        assertEq(currentId, 1);

        // Record successful execution
        vm.prank(address(provider1));
        executionCoordinator.recordSuccessfulExecution();

        // Unlock
        vm.prank(address(provider1));
        executionCoordinator.unlockExecution();

        // Check history
        ExecutionCoordinator.ExecutionRecord memory record = executionCoordinator.getExecutionRecord(currentId);
        assertEq(record.provider, address(provider1));
        assertEq(uint256(record.status), uint256(ExecutionCoordinator.ExecutionStatus.Executed));
    }

    function testRecordFailedExecution() public {
        // Lock execution
        vm.prank(address(provider1));
        executionCoordinator.lockExecution();

        uint256 currentId = executionCoordinator.currentExecutionId();

        // Record failed execution
        vm.prank(address(provider1));
        executionCoordinator.recordFailedExecution("Test failure");

        // Unlock
        vm.prank(address(provider1));
        executionCoordinator.unlockExecution();

        // Check history
        ExecutionCoordinator.ExecutionRecord memory record = executionCoordinator.getExecutionRecord(currentId);
        assertEq(record.provider, address(provider1));
        assertEq(uint256(record.status), uint256(ExecutionCoordinator.ExecutionStatus.Failed));
        assertEq(record.reason, "Test failure");
    }

    function testProviderConditionChecks() public {
        // Test when distribution is ready
        (bool needsExecution,) = provider1.checkCondition();
        assertTrue(needsExecution);

        // Test when distribution is not ready
        cycleManager.setDistributionReady(false);
        (needsExecution,) = provider1.checkCondition();
        assertFalse(needsExecution);

        // Test when provider is inactive
        cycleManager.setDistributionReady(true);
        vm.prank(owner);
        provider1.setActive(false);
        (needsExecution,) = provider1.checkCondition();
        assertFalse(needsExecution);
    }

    function testMultipleProvidersCoordination() public {
        // Both providers should see execution is needed
        (bool needs1,) = provider1.checkCondition();
        (bool needs2,) = provider2.checkCondition();
        assertTrue(needs1);
        assertTrue(needs2);

        // Provider 1 locks
        vm.prank(address(provider1));
        executionCoordinator.lockExecution();

        // Provider 2 cannot lock while provider 1 has lock
        vm.prank(address(provider2));
        bool canLock = executionCoordinator.lockExecution();
        assertFalse(canLock);

        // Provider 1 completes and unlocks
        vm.prank(address(provider1));
        executionCoordinator.recordSuccessfulExecution();
        vm.prank(address(provider1));
        executionCoordinator.unlockExecution();

        // Now provider 2 can lock
        vm.prank(address(provider2));
        canLock = executionCoordinator.lockExecution();
        assertTrue(canLock);
    }

    function testUnauthorizedUnlock() public {
        // Provider 1 locks
        vm.prank(address(provider1));
        executionCoordinator.lockExecution();

        // Provider 2 cannot unlock provider 1's lock
        vm.expectRevert(ExecutionCoordinator.UnauthorizedUnlock.selector);
        vm.prank(address(provider2));
        executionCoordinator.unlockExecution();
    }

    function testExecutionStatus() public {
        // Initial status should be Idle
        ExecutionCoordinator.ExecutionStatus status = executionCoordinator.getExecutionStatus();
        assertEq(uint256(status), uint256(ExecutionCoordinator.ExecutionStatus.Idle));

        // During lock should be Locked
        vm.prank(address(provider1));
        executionCoordinator.lockExecution();
        status = executionCoordinator.getExecutionStatus();
        assertEq(uint256(status), uint256(ExecutionCoordinator.ExecutionStatus.Locked));

        // After successful execution
        vm.prank(address(provider1));
        executionCoordinator.recordSuccessfulExecution();
        vm.prank(address(provider1));
        executionCoordinator.unlockExecution();

        status = executionCoordinator.getExecutionStatus();
        assertEq(uint256(status), uint256(ExecutionCoordinator.ExecutionStatus.Executed));
    }

    function testCycleManagerIntegration() public {
        // Test cycle info
        (uint256 cycleNum, uint256 startBlock, uint256 endBlock) = cycleManager.getCycleInfo();
        assertEq(cycleNum, 1);
        assertEq(startBlock, block.number);
        assertEq(endBlock, block.number);

        // Start new cycle
        cycleManager.startNewCycle();
        (cycleNum,,) = cycleManager.getCycleInfo();
        assertEq(cycleNum, 2);
        assertEq(cycleManager.getBlocksUntilNextCycle(), 100);

        // Test cycle length
        cycleManager.setCycleLength(200);
        assertEq(cycleManager.getCycleLength(), 200);
    }

    function testDistributionModuleIntegration() public {
        // Test normal distribution
        distributionModule.distribute();
        assertEq(distributionModule.distributeCallCount(), 1);

        // Test failed distribution
        distributionModule.setShouldRevert(true);
        vm.expectRevert("Distribution failed");
        distributionModule.distribute();
        assertEq(distributionModule.distributeCallCount(), 1);

        // Test distribution data
        uint256[] memory dist = distributionModule.getCurrentDistribution();
        assertEq(dist.length, 3);
        assertEq(dist[0], 40);
        assertEq(dist[1], 35);
        assertEq(dist[2], 25);
    }
}
