// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AutomationProviderBase.sol";
import "../EnhancedDistributionManager.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

/// @title ChainlinkAutomationWithPayment
/// @notice Chainlink Keeper compatible automation with payment support
/// @dev Implements Chainlink automation interface with integrated payment handling
contract ChainlinkAutomationWithPayment is AutomationProviderBase, AutomationCompatibleInterface {
    /// @notice Constructor
    /// @param _distributionManager Address of the distribution manager
    /// @param _paymentToken Address of the payment token (yield token)
    /// @param _paymentReceiver Address to receive automation payments
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

    /// @notice Chainlink-compatible upkeep check
    /// @dev Called by Chainlink nodes to check if work needs to be performed
    /// @param checkData Not used but required by Chainlink interface
    /// @return upkeepNeeded Whether upkeep is needed
    /// @return performData The data to pass to performUpkeep
    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = isDistributionReady();
        performData = upkeepNeeded ? getAutomationData() : new bytes(0);
    }

    /// @notice Chainlink-compatible upkeep execution
    /// @dev Called by Chainlink nodes when checkUpkeep returns true
    /// @param performData The data returned by checkUpkeep
    function performUpkeep(bytes calldata performData) external override {
        executeDistribution();
    }

    /// @notice Get detailed upkeep information
    /// @return ready Whether upkeep is needed
    /// @return reason Reason if not ready
    /// @return estimatedPayment Estimated payment for this execution
    function getUpkeepInfo() external view returns (bool ready, string memory reason, uint256 estimatedPayment) {
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

        // Calculate estimated payment if distribution would happen
        if (ready && paymentConfig.requiresPayment) {
            // This is a simplified estimation - actual yield would come from yield module
            (estimatedPayment,) = calculatePayment(paymentConfig.minYieldThreshold);
        }
    }
}
