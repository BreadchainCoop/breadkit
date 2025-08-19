// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../interfaces/IDistributionManager.sol";
import "../../interfaces/IAutomationPaymentProvider.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AutomationProviderBase
/// @notice Abstract base contract for automation providers with payment capabilities
/// @dev Inherit this contract to create provider-specific automation implementations with payment support
abstract contract AutomationProviderBase is IDistributionManager, IAutomationPaymentProvider, Ownable {
    using SafeERC20 for IERC20;

    IDistributionManager public immutable distributionManager;
    IERC20 public immutable paymentToken;
    PaymentConfig public paymentConfig;

    event AutomationExecuted(address indexed executor, uint256 blockNumber, uint256 paymentReceived);

    error NotResolved();
    error InvalidPaymentConfig();
    error PaymentProcessingFailed();

    constructor(
        address _distributionManager,
        address _paymentToken,
        PaymentConfig memory _initialConfig
    ) Ownable(msg.sender) {
        require(_distributionManager != address(0), "Invalid distribution manager");
        require(_paymentToken != address(0), "Invalid payment token");
        distributionManager = IDistributionManager(_distributionManager);
        paymentToken = IERC20(_paymentToken);
        _validateAndSetConfig(_initialConfig);
    }

    /// @notice Checks if distribution is ready
    /// @dev Delegates to DistributionManager for condition checking
    /// @return ready Whether the distribution conditions are met
    function isDistributionReady() public view virtual override returns (bool ready) {
        return distributionManager.isDistributionReady();
    }

    /// @notice Gets the automation data for execution
    /// @dev Returns encoded function call data for automation providers
    /// @return execPayload The encoded function call data
    function getAutomationData() public view virtual returns (bytes memory execPayload) {
        if (isDistributionReady()) {
            return abi.encodeWithSelector(this.executeDistribution.selector);
        }
        return new bytes(0);
    }

    /// @notice Executes the distribution
    /// @dev Delegates to DistributionManager for execution
    function executeDistribution() public virtual override {
        if (!distributionManager.isDistributionReady()) revert NotResolved();

        // Execute distribution (payment will be handled by EnhancedDistributionManager)
        distributionManager.executeDistribution();

        emit AutomationExecuted(msg.sender, block.number, 0);
    }

    /// @notice Gets the payment configuration
    function getPaymentConfig() external view override returns (PaymentConfig memory) {
        return paymentConfig;
    }

    /// @notice Calculates the required payment for a given yield amount
    function calculatePayment(uint256 yieldAmount)
        public
        view
        override
        returns (uint256 paymentAmount, uint256 remainingYield)
    {
        if (!paymentConfig.requiresPayment) {
            return (0, yieldAmount);
        }

        // Calculate fixed fee
        paymentAmount = paymentConfig.fixedFee;

        // Calculate percentage fee
        if (paymentConfig.percentageFee > 0) {
            uint256 percentageAmount = (yieldAmount * paymentConfig.percentageFee) / 10000;
            paymentAmount += percentageAmount;
        }

        // Apply max fee cap
        if (paymentConfig.maxFeeCap > 0 && paymentAmount > paymentConfig.maxFeeCap) {
            paymentAmount = paymentConfig.maxFeeCap;
        }

        // Ensure payment doesn't exceed yield
        if (paymentAmount > yieldAmount) {
            paymentAmount = yieldAmount;
            remainingYield = 0;
        } else {
            remainingYield = yieldAmount - paymentAmount;
        }
    }

    /// @notice Checks if there's sufficient yield to cover automation costs
    function hasSufficientYield(uint256 yieldAmount)
        public
        view
        override
        returns (bool sufficient, uint256 requiredAmount)
    {
        if (!paymentConfig.requiresPayment) {
            return (true, 0);
        }

        // Check against minimum threshold
        requiredAmount = paymentConfig.minYieldThreshold;
        if (requiredAmount == 0) {
            // If no threshold set, just check if payment can be covered
            (uint256 payment,) = calculatePayment(yieldAmount);
            requiredAmount = payment;
        }

        sufficient = yieldAmount >= requiredAmount;
    }

    /// @notice Updates the payment configuration
    function updatePaymentConfig(PaymentConfig calldata config) external override onlyOwner {
        _validateAndSetConfig(config);
    }

    /// @notice Processes payment for automation execution
    function processPayment(uint256 yieldAmount) external override returns (uint256 paymentAmount) {
        if (!paymentConfig.requiresPayment) {
            return 0;
        }

        (paymentAmount,) = calculatePayment(yieldAmount);

        if (paymentAmount > 0 && paymentConfig.paymentReceiver != address(0)) {
            // Transfer payment from caller (EnhancedDistributionManager)
            paymentToken.safeTransferFrom(msg.sender, paymentConfig.paymentReceiver, paymentAmount);
            
            emit AutomationPaymentMade(
                address(this),
                paymentConfig.paymentReceiver,
                paymentAmount,
                yieldAmount
            );
        }

        return paymentAmount;
    }

    /// @notice Internal function to validate and set payment configuration
    function _validateAndSetConfig(PaymentConfig memory config) internal {
        if (config.requiresPayment) {
            if (config.paymentReceiver == address(0)) revert InvalidPaymentConfig();
            if (config.percentageFee > 10000) revert InvalidPaymentConfig(); // Max 100%
        }
        
        paymentConfig = config;
        emit PaymentConfigUpdated(address(this), config);
    }

    /// @notice Allows owner to update payment receiver
    function updatePaymentReceiver(address newReceiver) external onlyOwner {
        require(newReceiver != address(0), "Invalid receiver");
        paymentConfig.paymentReceiver = newReceiver;
        emit PaymentConfigUpdated(address(this), paymentConfig);
    }

    /// @notice Allows owner to toggle payment requirement
    function setPaymentRequired(bool required) external onlyOwner {
        paymentConfig.requiresPayment = required;
        emit PaymentConfigUpdated(address(this), paymentConfig);
    }
}