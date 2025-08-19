// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AutomationProviderBase.sol";
import "../EnhancedDistributionManager.sol";

/// @title GelatoAutomationWithPayment
/// @notice Gelato Network compatible automation with payment support
/// @dev Implements Gelato automation interface with integrated payment handling
contract GelatoAutomationWithPayment is AutomationProviderBase {
    /// @notice Constructor
    /// @param _distributionManager Address of the distribution manager
    /// @param _paymentToken Address of the payment token (yield token)
    /// @param _paymentReceiver Address to receive automation payments (typically Gelato treasury)
    /// @param _fixedFee Fixed fee per execution
    /// @param _percentageFee Percentage fee (in basis points)
    /// @param _minYieldThreshold Minimum yield required before execution
    constructor(
        address _distributionManager,
        address _paymentToken,
        address _paymentReceiver,
        uint256 _fixedFee,
        uint256 _percentageFee,
        uint256 _minYieldThreshold
    )
        AutomationProviderBase(
            _distributionManager,
            _paymentToken,
            PaymentConfig({
                requiresPayment: true,
                fixedFee: _fixedFee,
                percentageFee: _percentageFee,
                minYieldThreshold: _minYieldThreshold,
                paymentReceiver: _paymentReceiver,
                maxFeeCap: 0 // Can be set later if needed
            })
        )
    {}

    /// @notice Gelato-compatible resolver function
    /// @dev Called by Gelato executors to check if work needs to be performed
    /// @return canExec Whether execution can proceed
    /// @return execPayload The calldata to execute
    function checker() external view returns (bool canExec, bytes memory execPayload) {
        canExec = isDistributionReady();
        execPayload = canExec ? getAutomationData() : new bytes(0);
    }

    /// @notice Gelato-compatible execution function
    /// @dev Called by Gelato executors when checker returns true
    /// @param execData The data for execution (not used but can be for validation)
    function execute(bytes calldata execData) external {
        executeDistribution();
    }

    /// @notice Get detailed task information for Gelato
    /// @return ready Whether task is ready for execution
    /// @return reason Reason if not ready
    /// @return estimatedGasUsed Estimated gas for execution
    /// @return estimatedPayment Estimated payment for this execution
    function getTaskInfo()
        external
        view
        returns (bool ready, string memory reason, uint256 estimatedGasUsed, uint256 estimatedPayment)
    {
        ready = isDistributionReady();

        if (!ready) {
            // Try to get reason from distribution manager if it has enhanced version
            try EnhancedDistributionManager(address(distributionManager)).getDistributionReadiness() returns (
                bool, string memory r, uint256, uint256
            ) {
                reason = r;
            } catch {
                reason = "Distribution not ready";
            }
        }

        // Estimate gas usage (this is a rough estimate)
        estimatedGasUsed = 300000; // Base estimate for distribution execution

        // Calculate estimated payment if distribution would happen
        if (ready && paymentConfig.requiresPayment) {
            // This is a simplified estimation - actual yield would come from yield module
            (estimatedPayment,) = calculatePayment(paymentConfig.minYieldThreshold);
        }
    }

    /// @notice Gelato-specific function to validate execution conditions
    /// @dev Can be called by Gelato infrastructure for pre-execution checks
    /// @return valid Whether execution conditions are valid
    /// @return message Validation message
    function validateExecution() external view returns (bool valid, string memory message) {
        if (!isDistributionReady()) {
            return (false, "Distribution conditions not met");
        }

        // Additional Gelato-specific validations could go here

        return (true, "Ready for execution");
    }
}
