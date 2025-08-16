// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/interfaces/ICycleManager.sol";
import "../../src/interfaces/IDistributionModule.sol";

// Simplified automation module for testing without upgradeable pattern
contract SimpleAutomationModule {
    ICycleManager public cycleManager;
    IDistributionModule public distributionModule;

    uint256 public lastExecutionBlock;
    uint256 public minBlocksBetweenExecutions = 50;
    bool public automationEnabled = true;

    mapping(address => bool) public authorizedCallers;
    address public owner;

    event DistributionExecuted(address indexed executor, uint256 blockNumber);
    event AutomationStatusChanged(bool enabled);
    event CallerAuthorizationChanged(address indexed caller, bool authorized);

    error NotAuthorized();
    error AutomationDisabled();
    error TooSoonToExecute();
    error DistributionNotReady();
    error ZeroAddress();

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyAuthorized() {
        if (!authorizedCallers[msg.sender] && msg.sender != owner) {
            revert NotAuthorized();
        }
        _;
    }

    constructor(address _owner) {
        owner = _owner;
    }

    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        return _checkExecution();
    }

    function performUpkeep(bytes calldata) external onlyAuthorized {
        _executeDistribution();
    }

    function checker() external view returns (bool canExec, bytes memory execPayload) {
        return _checkExecution();
    }

    function execute(bytes calldata) external onlyAuthorized {
        _executeDistribution();
    }

    function executeAutomation() external onlyAuthorized {
        _executeDistribution();
    }

    function _checkExecution() internal view returns (bool needed, bytes memory data) {
        if (!automationEnabled) {
            return (false, "Automation disabled");
        }

        if (lastExecutionBlock > 0 && block.number < lastExecutionBlock + minBlocksBetweenExecutions) {
            return (false, "Too soon");
        }

        if (address(cycleManager) == address(0) || !cycleManager.isDistributionReady()) {
            return (false, "Distribution not ready");
        }

        return (true, abi.encodeWithSelector(this.executeAutomation.selector));
    }

    function _executeDistribution() internal {
        if (!automationEnabled) revert AutomationDisabled();
        if (lastExecutionBlock > 0 && block.number < lastExecutionBlock + minBlocksBetweenExecutions) {
            revert TooSoonToExecute();
        }
        if (!cycleManager.isDistributionReady()) revert DistributionNotReady();

        lastExecutionBlock = block.number;

        distributionModule.distribute();
        cycleManager.startNewCycle();

        emit DistributionExecuted(msg.sender, block.number);
    }

    function setCallerAuthorization(address caller, bool authorized) external onlyOwner {
        authorizedCallers[caller] = authorized;
        emit CallerAuthorizationChanged(caller, authorized);
    }

    function setAutomationEnabled(bool enabled) external onlyOwner {
        automationEnabled = enabled;
        emit AutomationStatusChanged(enabled);
    }

    function setMinBlocksBetweenExecutions(uint256 blocks) external onlyOwner {
        minBlocksBetweenExecutions = blocks;
    }

    function setCycleManager(address _cycleManager) external onlyOwner {
        if (_cycleManager == address(0)) revert ZeroAddress();
        cycleManager = ICycleManager(_cycleManager);
    }

    function setDistributionModule(address _distributionModule) external onlyOwner {
        if (_distributionModule == address(0)) revert ZeroAddress();
        distributionModule = IDistributionModule(_distributionModule);
    }

    function emergencyExecute() external onlyOwner {
        if (!cycleManager.isDistributionReady()) revert DistributionNotReady();

        distributionModule.distribute();
        cycleManager.startNewCycle();

        emit DistributionExecuted(msg.sender, block.number);
    }
}

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
}

contract MockDistributionModule is IDistributionModule {
    uint256 public distributeCallCount;

    function distribute() external {
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
}

contract AutomationModuleSimpleTest is Test {
    SimpleAutomationModule public automation;
    MockCycleManager public cycleManager;
    MockDistributionModule public distributionModule;

    address public owner = address(0x1);
    address public chainlinkKeeper = address(0x2);
    address public gelatoExecutor = address(0x3);
    address public unauthorizedCaller = address(0x4);

    event DistributionExecuted(address indexed executor, uint256 blockNumber);

    function setUp() public {
        cycleManager = new MockCycleManager();
        distributionModule = new MockDistributionModule();

        vm.prank(owner);
        automation = new SimpleAutomationModule(owner);

        vm.startPrank(owner);
        automation.setCycleManager(address(cycleManager));
        automation.setDistributionModule(address(distributionModule));
        automation.setCallerAuthorization(chainlinkKeeper, true);
        automation.setCallerAuthorization(gelatoExecutor, true);
        vm.stopPrank();
    }

    function testChainlinkAutomation() public {
        (bool upkeepNeeded, bytes memory performData) = automation.checkUpkeep("");
        assertTrue(upkeepNeeded);
        assertGt(performData.length, 0);

        vm.expectEmit(true, false, false, true);
        emit DistributionExecuted(chainlinkKeeper, block.number);

        vm.prank(chainlinkKeeper);
        automation.performUpkeep(performData);

        assertEq(distributionModule.distributeCallCount(), 1);
        assertEq(automation.lastExecutionBlock(), block.number);
    }

    function testGelatoAutomation() public {
        (bool canExec, bytes memory execPayload) = automation.checker();
        assertTrue(canExec);
        assertGt(execPayload.length, 0);

        vm.expectEmit(true, false, false, true);
        emit DistributionExecuted(gelatoExecutor, block.number);

        vm.prank(gelatoExecutor);
        automation.execute(execPayload);

        assertEq(distributionModule.distributeCallCount(), 1);
    }

    function testUnauthorizedCallerReverts() public {
        vm.expectRevert(SimpleAutomationModule.NotAuthorized.selector);
        vm.prank(unauthorizedCaller);
        automation.executeAutomation();
    }

    function testOwnerCanExecute() public {
        vm.prank(owner);
        automation.executeAutomation();
        assertEq(distributionModule.distributeCallCount(), 1);
    }

    function testMinBlocksBetweenExecutions() public {
        vm.prank(chainlinkKeeper);
        automation.executeAutomation();
        assertEq(distributionModule.distributeCallCount(), 1);

        (bool upkeepNeeded,) = automation.checkUpkeep("");
        assertFalse(upkeepNeeded);

        vm.expectRevert(SimpleAutomationModule.TooSoonToExecute.selector);
        vm.prank(chainlinkKeeper);
        automation.executeAutomation();

        vm.roll(block.number + 51);

        (upkeepNeeded,) = automation.checkUpkeep("");
        assertTrue(upkeepNeeded);

        vm.prank(chainlinkKeeper);
        automation.executeAutomation();
        assertEq(distributionModule.distributeCallCount(), 2);
    }

    function testAutomationCanBeDisabled() public {
        vm.prank(owner);
        automation.setAutomationEnabled(false);

        (bool upkeepNeeded,) = automation.checkUpkeep("");
        assertFalse(upkeepNeeded);

        vm.expectRevert(SimpleAutomationModule.AutomationDisabled.selector);
        vm.prank(chainlinkKeeper);
        automation.executeAutomation();
    }

    function testDistributionNotReady() public {
        cycleManager.setDistributionReady(false);

        (bool upkeepNeeded,) = automation.checkUpkeep("");
        assertFalse(upkeepNeeded);

        vm.expectRevert(SimpleAutomationModule.DistributionNotReady.selector);
        vm.prank(chainlinkKeeper);
        automation.executeAutomation();
    }

    function testEmergencyExecution() public {
        vm.prank(owner);
        automation.setAutomationEnabled(false);

        vm.prank(owner);
        automation.emergencyExecute();
        assertEq(distributionModule.distributeCallCount(), 1);
    }

    function testMultipleProvidersWork() public {
        // Chainlink executes
        vm.prank(chainlinkKeeper);
        automation.executeAutomation();
        assertEq(distributionModule.distributeCallCount(), 1);

        vm.roll(block.number + 100);

        // Gelato executes
        vm.prank(gelatoExecutor);
        automation.executeAutomation();
        assertEq(distributionModule.distributeCallCount(), 2);
    }

    function testSetMinBlocksBetweenExecutions() public {
        vm.prank(owner);
        automation.setMinBlocksBetweenExecutions(100);

        vm.prank(chainlinkKeeper);
        automation.executeAutomation();

        vm.roll(block.number + 99);
        vm.expectRevert(SimpleAutomationModule.TooSoonToExecute.selector);
        vm.prank(chainlinkKeeper);
        automation.executeAutomation();

        vm.roll(block.number + 1);
        vm.prank(chainlinkKeeper);
        automation.executeAutomation();
        assertEq(distributionModule.distributeCallCount(), 2);
    }

    function testCallerAuthorizationManagement() public {
        vm.prank(owner);
        automation.setCallerAuthorization(chainlinkKeeper, false);

        vm.expectRevert(SimpleAutomationModule.NotAuthorized.selector);
        vm.prank(chainlinkKeeper);
        automation.executeAutomation();

        vm.prank(owner);
        automation.setCallerAuthorization(chainlinkKeeper, true);

        vm.prank(chainlinkKeeper);
        automation.executeAutomation();
        assertEq(distributionModule.distributeCallCount(), 1);
    }
}
