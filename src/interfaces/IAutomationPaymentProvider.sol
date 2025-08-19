// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAutomationPaymentProvider
/// @notice Interface for automation providers that require payment from yield
/// @dev Defines how automation providers calculate and receive payments for their services
interface IAutomationPaymentProvider {
    /// @notice Struct containing payment configuration for an automation provider
    struct PaymentConfig {
        /// @notice Whether this provider requires payment
        bool requiresPayment;
        /// @notice Fixed fee amount per execution (in yield token units)
        uint256 fixedFee;
        /// @notice Percentage fee from yield (basis points, 10000 = 100%)
        uint256 percentageFee;
        /// @notice Minimum yield required before execution (includes fees)
        uint256 minYieldThreshold;
        /// @notice Address to receive the payment
        address paymentReceiver;
        /// @notice Maximum fee cap per execution
        uint256 maxFeeCap;
    }

    /// @notice Emitted when automation payment is made
    /// @param provider Address of the automation provider
    /// @param receiver Address that received the payment
    /// @param amount Amount paid
    /// @param yieldAmount Total yield amount before payment
    event AutomationPaymentMade(
        address indexed provider, address indexed receiver, uint256 amount, uint256 yieldAmount
    );

    /// @notice Emitted when payment configuration is updated
    /// @param provider Address of the automation provider
    /// @param config New payment configuration
    event PaymentConfigUpdated(address indexed provider, PaymentConfig config);

    /// @notice Gets the payment configuration for this provider
    /// @return config The current payment configuration
    function getPaymentConfig() external view returns (PaymentConfig memory config);

    /// @notice Calculates the required payment for a given yield amount
    /// @param yieldAmount The total yield available for distribution
    /// @return paymentAmount The amount to be paid to the automation provider
    /// @return remainingYield The yield remaining after payment
    function calculatePayment(uint256 yieldAmount)
        external
        view
        returns (uint256 paymentAmount, uint256 remainingYield);

    /// @notice Checks if there's sufficient yield to cover automation costs
    /// @param yieldAmount The total yield available
    /// @return sufficient Whether the yield is sufficient to cover costs
    /// @return requiredAmount The minimum amount needed (including fees)
    function hasSufficientYield(uint256 yieldAmount) external view returns (bool sufficient, uint256 requiredAmount);

    /// @notice Updates the payment configuration
    /// @dev Only callable by authorized admin
    /// @param config New payment configuration
    function updatePaymentConfig(PaymentConfig calldata config) external;

    /// @notice Processes payment for automation execution
    /// @dev Called after successful automation execution
    /// @param yieldAmount The total yield amount being distributed
    /// @return paymentAmount The amount paid to the provider
    function processPayment(uint256 yieldAmount) external returns (uint256 paymentAmount);
}
