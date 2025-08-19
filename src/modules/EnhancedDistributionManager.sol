// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IDistributionManager.sol";
import "../interfaces/IDistributionModule.sol";
import "../interfaces/IAutomationPaymentProvider.sol";
import "../interfaces/IYieldModule.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title EnhancedDistributionManager
/// @notice Distribution manager with integrated automation provider payment support
/// @dev Ensures sufficient yield exists to cover automation costs before allowing distribution
contract EnhancedDistributionManager is IDistributionManager, Ownable {
    using SafeERC20 for IERC20;

    IDistributionModule public immutable distributionModule;
    IYieldModule public immutable yieldModule;
    IAutomationPaymentProvider public automationProvider;
    IERC20 public immutable yieldToken;

    uint256 public cycleLength;
    uint256 public lastDistributionBlock;
    uint256 public currentCycleNumber;
    uint256 public minYieldRequired;

    bool public isEnabled = true;
    bool public automationPaymentEnabled = true;

    event DistributionExecuted(
        uint256 blockNumber, uint256 totalYield, uint256 automationPayment, uint256 distributedYield
    );
    event AutomationProviderUpdated(address indexed oldProvider, address indexed newProvider);
    event AutomationPaymentToggled(bool enabled);
    event MinYieldRequiredUpdated(uint256 oldAmount, uint256 newAmount);
    event CycleLengthUpdated(uint256 oldLength, uint256 newLength);

    error InsufficientYieldForAutomation(uint256 available, uint256 required);
    error InvalidConfiguration();
    error SystemDisabled();
    error TooSoonToDistribute();
    error NoAutomationProvider();

    constructor(
        address _distributionModule,
        address _yieldModule,
        address _yieldToken,
        uint256 _cycleLength,
        uint256 _minYieldRequired
    ) Ownable(msg.sender) {
        require(_distributionModule != address(0), "Invalid distribution module");
        require(_yieldModule != address(0), "Invalid yield module");
        require(_yieldToken != address(0), "Invalid yield token");
        require(_cycleLength > 0, "Invalid cycle length");

        distributionModule = IDistributionModule(_distributionModule);
        yieldModule = IYieldModule(_yieldModule);
        yieldToken = IERC20(_yieldToken);
        cycleLength = _cycleLength;
        minYieldRequired = _minYieldRequired;
        lastDistributionBlock = block.number;
        currentCycleNumber = 1;
    }

    /// @notice Checks if distribution is ready, including automation payment requirements
    function isDistributionReady() public view override returns (bool ready) {
        // Check basic conditions
        if (!isEnabled) return false;
        if (block.number < lastDistributionBlock + cycleLength) return false;

        // Get available yield
        uint256 availableYield = yieldModule.yieldAccrued();

        // Check minimum yield requirement
        if (availableYield < minYieldRequired) return false;

        // Check automation payment requirements if enabled
        if (automationPaymentEnabled && address(automationProvider) != address(0)) {
            (bool sufficient,) = automationProvider.hasSufficientYield(availableYield);
            if (!sufficient) return false;
        }

        // Validate distribution conditions
        (bool canDistribute,) = distributionModule.validateDistribution();
        return canDistribute;
    }

    /// @notice Executes the distribution with automation payment handling
    function executeDistribution() external override {
        // Verify all conditions
        if (!isEnabled) revert SystemDisabled();
        if (block.number < lastDistributionBlock + cycleLength) revert TooSoonToDistribute();

        uint256 availableYield = yieldModule.yieldAccrued();
        if (availableYield < minYieldRequired) {
            revert InsufficientYieldForAutomation(availableYield, minYieldRequired);
        }

        uint256 automationPayment = 0;
        uint256 yieldForDistribution = availableYield;

        // Process automation payment if enabled
        if (automationPaymentEnabled && address(automationProvider) != address(0)) {
            (bool sufficient, uint256 requiredAmount) = automationProvider.hasSufficientYield(availableYield);
            if (!sufficient) {
                revert InsufficientYieldForAutomation(availableYield, requiredAmount);
            }

            // Claim yield from yield module
            yieldModule.claimYield(availableYield, address(this));

            // Approve automation provider to take payment
            yieldToken.approve(address(automationProvider), availableYield);

            // Process payment to automation provider
            automationPayment = automationProvider.processPayment(availableYield);
            yieldForDistribution = availableYield - automationPayment;

            // Transfer remaining yield to distribution module
            if (yieldForDistribution > 0) {
                yieldToken.safeTransfer(address(distributionModule), yieldForDistribution);
            }
        } else {
            // Direct claim to distribution module if no automation payment
            yieldModule.claimYield(availableYield, address(distributionModule));
        }

        // Update state
        lastDistributionBlock = block.number;
        currentCycleNumber++;

        // Execute distribution
        distributionModule.distributeYield();

        // Emit event
        emit DistributionExecuted(block.number, availableYield, automationPayment, yieldForDistribution);
    }

    /// @notice Sets the automation provider
    /// @param _provider Address of the automation payment provider
    function setAutomationProvider(address _provider) external onlyOwner {
        address oldProvider = address(automationProvider);
        automationProvider = IAutomationPaymentProvider(_provider);
        emit AutomationProviderUpdated(oldProvider, _provider);
    }

    /// @notice Toggles automation payment requirement
    /// @param _enabled Whether automation payment is required
    function setAutomationPaymentEnabled(bool _enabled) external onlyOwner {
        automationPaymentEnabled = _enabled;
        emit AutomationPaymentToggled(_enabled);
    }

    /// @notice Sets minimum yield required for distribution
    /// @param _minYield New minimum yield requirement
    function setMinYieldRequired(uint256 _minYield) external onlyOwner {
        uint256 oldAmount = minYieldRequired;
        minYieldRequired = _minYield;
        emit MinYieldRequiredUpdated(oldAmount, _minYield);
    }

    /// @notice Sets the cycle length
    /// @param _cycleLength New cycle length in blocks
    function setCycleLength(uint256 _cycleLength) external onlyOwner {
        require(_cycleLength > 0, "Invalid cycle length");
        uint256 oldLength = cycleLength;
        cycleLength = _cycleLength;
        emit CycleLengthUpdated(oldLength, _cycleLength);
    }

    /// @notice Emergency pause
    function pause() external onlyOwner {
        isEnabled = false;
    }

    /// @notice Resume after emergency
    function unpause() external onlyOwner {
        isEnabled = true;
    }

    /// @notice Get distribution readiness details
    /// @return ready Whether distribution is ready
    /// @return reason Reason if not ready
    /// @return availableYield Current available yield
    /// @return requiredYield Minimum yield required (including automation fees)
    function getDistributionReadiness()
        external
        view
        returns (bool ready, string memory reason, uint256 availableYield, uint256 requiredYield)
    {
        ready = true;
        availableYield = yieldModule.yieldAccrued();
        requiredYield = minYieldRequired;

        if (!isEnabled) {
            return (false, "System is disabled", availableYield, requiredYield);
        }

        if (block.number < lastDistributionBlock + cycleLength) {
            return (false, "Too soon for next distribution", availableYield, requiredYield);
        }

        if (availableYield < minYieldRequired) {
            return (false, "Insufficient yield", availableYield, requiredYield);
        }

        if (automationPaymentEnabled && address(automationProvider) != address(0)) {
            (bool sufficient, uint256 required) = automationProvider.hasSufficientYield(availableYield);
            if (!sufficient) {
                return (false, "Insufficient yield for automation payment", availableYield, required);
            }
            requiredYield = required;
        }

        (bool canDistribute, string memory validateReason) = distributionModule.validateDistribution();
        if (!canDistribute) {
            return (false, validateReason, availableYield, requiredYield);
        }

        return (true, "", availableYield, requiredYield);
    }

    /// @notice Get cycle information
    /// @return cycleNumber Current cycle number
    /// @return startBlock Start block of current cycle
    /// @return endBlock Expected end block of current cycle
    /// @return blocksRemaining Blocks until next distribution
    function getCycleInfo()
        external
        view
        returns (uint256 cycleNumber, uint256 startBlock, uint256 endBlock, uint256 blocksRemaining)
    {
        cycleNumber = currentCycleNumber;
        startBlock = lastDistributionBlock;
        endBlock = lastDistributionBlock + cycleLength;
        blocksRemaining = endBlock > block.number ? endBlock - block.number : 0;
    }
}
